defmodule AbakusWeb.BankConnectionsLive do
  @moduledoc """
  Import & Sync's Bankverbindungen, the budget owner's bank connections through Enable Banking (ADR 0021): a card
  per connection with its consent and the accounts its bank accounts feed, and "Bank verbinden", which picks a bank
  and sends the owner there to consent (through `AbakusWeb.BankConnectionController`). Back from the bank, the
  owner assigns each bank account to an account or leaves it unlinked (`:accounts`), with the date to fetch from:
  choosing an account sets it to the day after its last reconcile, else today. Without the configuration the tab
  says bank sync is not set up.

  A card shows the connection's last fetch, its last five sync runs and the error of a failed one. "Jetzt abrufen"
  fetches at once with the PSU data of the owner's browser (the client's IP through the trusted proxies, its user
  agent), so the bank does not count it against its unattended fetches; a connection whose consent has ended does not
  fetch. "Freigabe erneuern" sends the owner to the bank for a new consent of the connection, which keeps its linked
  accounts.
  """
  use AbakusWeb, :live_view

  alias Abakus.{BankSync, Format}
  alias Abakus.BankSync.Connection
  alias Abakus.Ledger.Account
  alias Abakus.MCP.Access
  alias AbakusWeb.{BankConnectionController, ImportSync, NotFoundError}

  @countries [
    {"Belgien", "BE"},
    {"Bulgarien", "BG"},
    {"Dänemark", "DK"},
    {"Deutschland", "DE"},
    {"Estland", "EE"},
    {"Finnland", "FI"},
    {"Frankreich", "FR"},
    {"Griechenland", "GR"},
    {"Irland", "IE"},
    {"Island", "IS"},
    {"Italien", "IT"},
    {"Kroatien", "HR"},
    {"Lettland", "LV"},
    {"Liechtenstein", "LI"},
    {"Litauen", "LT"},
    {"Luxemburg", "LU"},
    {"Malta", "MT"},
    {"Niederlande", "NL"},
    {"Norwegen", "NO"},
    {"Österreich", "AT"},
    {"Polen", "PL"},
    {"Portugal", "PT"},
    {"Rumänien", "RO"},
    {"Schweden", "SE"},
    {"Slowakei", "SK"},
    {"Slowenien", "SI"},
    {"Spanien", "ES"},
    {"Tschechien", "CZ"},
    {"Ungarn", "HU"},
    {"Zypern", "CY"}
  ]
  @country_names Map.new(@countries, fn {name, code} -> {code, name} end)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:import}
      account_groups={@account_groups}
      depot_sidebar={@depot_sidebar}
      account_dialog={@account_dialog}
    >
      <ImportSync.import_header
        tab={:bank_connections}
        current_scope={@current_scope}
        inbox={@depot_sidebar.inbox}
      >
        <:subtitle>Umsätze und Salden direkt von der Bank, über Enable Banking.</:subtitle>
      </ImportSync.import_header>
      <.empty_state
        :if={!@available}
        id="bank-sync-not-set-up"
        icon="landmark"
        plush="landmark"
        title="Bank-Sync ist nicht eingerichtet"
      >
        <p class="max-w-prose">
          Dafür braucht Abakus eine Anwendung bei Enable Banking: ihre ID in ENABLE_BANKING_APP_ID und den Pfad
          ihres privaten Schlüssels in ENABLE_BANKING_KEY_FILE. Als Redirect-URL der Anwendung
          <span class="wrap-anywhere font-medium">{@redirect_url}</span>
          eintragen.
        </p>
      </.empty_state>
      <div :if={@available} class="flex flex-col gap-8">
        <.assign_accounts
          :if={@live_action == :accounts}
          connection={@connection}
          links={@links}
          accounts={@accounts}
        />
        <section id="bank-connections" aria-label="Bankverbindungen" class="flex flex-col gap-4">
          <.empty_state
            :if={@connections == []}
            id="bank-connections-empty"
            icon="landmark"
            plush="landmark"
            title="Noch keine Bank verbunden"
          >
            Nach dem Verbinden holt Abakus die Umsätze der zugeordneten Konten von selbst.
          </.empty_state>
          <.connection
            :for={connection <- @connections}
            connection={connection}
            fetching={Map.has_key?(@fetching, connection.id)}
          />
        </section>
        <.connect_form countries={@countries} country={@country} bank={@bank} banks={@banks} />
      </div>
    </Layouts.app>
    """
  end

  attr :connection, :map, required: true
  attr :fetching, :boolean, required: true

  defp connection(assigns) do
    ~H"""
    <.card
      id={"bank-connection-#{@connection.id}"}
      bleed={:phone}
      title={@connection.bank_name}
      subtitle={
        join_meta([
          country_name(@connection.bank_country),
          consent_text(@connection),
          last_fetch_text(@connection)
        ])
      }
    >
      <:leading><.icon name="landmark" class="size-5 text-base-content/70" /></:leading>
      <:actions>
        <.button
          id={"bank-connection-#{@connection.id}-fetch"}
          size={:sm}
          icon="refresh-cw"
          loading={@fetching}
          disabled={!Connection.fetchable?(@connection)}
          phx-click="fetch"
          phx-value-id={@connection.id}
        >
          Jetzt abrufen
        </.button>
        <.button
          id={"bank-connection-#{@connection.id}-renew"}
          size={:sm}
          icon="key-round"
          variant={if Connection.expired?(@connection), do: :primary, else: :neutral}
          phx-click="renew"
          phx-value-id={@connection.id}
          phx-disable-with="Öffnet die Bank …"
        >
          Freigabe erneuern
        </.button>
        <.button
          id={"bank-connection-#{@connection.id}-assign"}
          size={:sm}
          patch={~p"/budget/bank-connections/#{@connection}/accounts"}
        >
          Konten zuordnen
        </.button>
        <.button
          id={"bank-connection-#{@connection.id}-remove"}
          size={:sm}
          variant={:ghost}
          icon="trash-2"
          icon_only
          label="Trennen"
          confirm={"#{@connection.bank_name} trennen?"}
          confirm_text="Abakus ruft dann nichts mehr von dieser Bank ab; was schon importiert ist, bleibt."
          confirm_label="Trennen"
          phx-click="remove"
          phx-value-id={@connection.id}
        />
      </:actions>
      <.alert
        :if={@connection.last_error}
        id={"bank-connection-#{@connection.id}-error"}
        tone={:error}
        title="Der letzte Abruf ist fehlgeschlagen"
        class="mt-2"
      >
        {@connection.last_error}
      </.alert>
      <:list>
        <.list flush>
          <.list_row
            :for={linked <- @connection.linked_accounts}
            id={"linked-account-#{linked.id}"}
            title={linked.name || format_iban(linked.iban)}
          >
            <:meta :if={linked.name && linked.iban}>{format_iban(linked.iban)}</:meta>
            <:trailing>
              <span :if={linked.account} class="text-sm">
                {join_meta([linked.account.name, "ab #{Format.date(linked.start_date)}"])}
              </span>
              <.badge :if={!linked.account}>nicht verknüpft</.badge>
            </:trailing>
          </.list_row>
        </.list>
      </:list>
      <:footer :if={@connection.sync_runs != []}>
        <p class="font-medium text-base-content">Letzte Abrufe</p>
        <ul id={"bank-connection-#{@connection.id}-runs"}>
          <li :for={run <- @connection.sync_runs} id={"sync-run-#{run.id}"} class="wrap-anywhere">
            {join_meta([Format.datetime(run.started_at), trigger_text(run.trigger), run_text(run)])}
          </li>
        </ul>
      </:footer>
    </.card>
    """
  end

  attr :connection, :map, required: true
  attr :links, :map, required: true
  attr :accounts, :list, required: true

  defp assign_accounts(assigns) do
    ~H"""
    <.card
      id="bank-accounts"
      bleed={:phone}
      title={"Konten von #{@connection.bank_name} zuordnen"}
      subtitle="Abakus holt die Umsätze eines Bankkontos ab dem gewählten Tag in das zugeordnete Konto."
    >
      <.empty_state
        :if={@connection.linked_accounts == []}
        id="bank-accounts-empty"
        icon="landmark"
        plush="landmark"
        title="Die Bank hat kein Konto freigegeben"
      >
        Der freie Zugang von Enable Banking sieht nur Konten, die in seinem Kontrollzentrum verknüpft sind. Dort
        verknüpfen und dann die Freigabe erneuern.
        <:action>
          <.button id="bank-accounts-back" patch={~p"/budget/bank-connections"}>Zurück</.button>
        </:action>
      </.empty_state>
      <form
        :if={@connection.linked_accounts != []}
        id="bank-accounts-form"
        phx-change="change_links"
        phx-submit="save_links"
      >
        <div
          :for={linked <- @connection.linked_accounts}
          id={"link-#{linked.id}"}
          class="grid gap-x-4 border-b border-base-content/10 py-4 first:pt-0 sm:grid-cols-3 sm:items-end"
        >
          <div class="text-sm sm:pb-2">
            <p class="font-medium">{linked.name || format_iban(linked.iban)}</p>
            <p :if={linked.name && linked.iban} class="text-base-content/70 whitespace-nowrap">
              {format_iban(linked.iban)}
            </p>
          </div>
          <.input
            type="select"
            id={"link-#{linked.id}-account"}
            name={"links[#{linked.id}][account_id]"}
            label="Abakus-Konto"
            options={account_options(@accounts, linked)}
            prompt="Nicht verknüpfen"
            value={@links[linked.id].account_id}
          />
          <.input
            :if={@links[linked.id].account_id}
            type="date"
            id={"link-#{linked.id}-start-date"}
            name={"links[#{linked.id}][start_date]"}
            label="Abrufen ab"
            value={@links[linked.id].start_date && Date.to_iso8601(@links[linked.id].start_date)}
          />
        </div>
        <.action_bar>
          <.button id="bank-accounts-cancel" patch={~p"/budget/bank-connections"}>Abbrechen</.button>
          <.button
            id="bank-accounts-save"
            type="submit"
            variant={:primary}
            phx-disable-with="Speichert …"
          >
            Zuordnen
          </.button>
        </.action_bar>
      </form>
    </.card>
    """
  end

  attr :countries, :list, required: true
  attr :country, :string, required: true
  attr :bank, :string, default: nil

  attr :banks, :any,
    required: true,
    doc: "nil while loading, else `{:ok, banks}` or `{:error, message}`"

  defp connect_form(assigns) do
    ~H"""
    <section id="bank-connect" aria-labelledby="bank-connect-heading">
      <.section_heading id="bank-connect-heading">Bank verbinden</.section_heading>
      <p class="mb-2 max-w-prose text-sm text-base-content/70">
        Abakus schickt dich zur Bank, um die Freigabe zu erteilen; danach ordnest du die Konten zu. Der freie
        Zugang von Enable Banking sieht nur Konten, die in seinem Kontrollzentrum verknüpft sind.
      </p>
      <form
        id="bank-connect-form"
        phx-change="change_connect"
        phx-submit="connect"
        class="grid gap-x-4 sm:grid-cols-2"
      >
        <.input
          type="select"
          id="bank-connect-country"
          name="country"
          label="Land"
          options={@countries}
          value={@country}
        />
        <.input
          type="select"
          id="bank-connect-bank"
          name="bank"
          label="Bank"
          options={bank_options(@banks)}
          prompt={bank_prompt(@banks)}
          value={@bank}
          disabled={!match?({:ok, [_ | _]}, @banks)}
          errors={bank_errors(@banks)}
        />
        <.action_bar class="sm:col-span-2">
          <.button
            id="bank-connect-submit"
            type="submit"
            variant={:primary}
            disabled={!@bank}
            phx-disable-with="Öffnet die Bank …"
          >
            Weiter zur Bank
          </.button>
        </.action_bar>
      </form>
    </section>
    """
  end

  defp bank_options({:ok, banks}), do: Enum.map(banks, & &1.name)
  defp bank_options(_loading_or_error), do: []

  defp bank_prompt(nil), do: "Lädt die Banken …"
  defp bank_prompt({:ok, []}), do: "Keine Bank in diesem Land"
  defp bank_prompt(_banks), do: "Bank wählen …"

  defp bank_errors({:error, message}), do: [message]
  defp bank_errors(_banks), do: []

  defp country_name(code), do: Map.get(@country_names, code, code)

  defp consent_text(connection) do
    if Connection.expired?(connection),
      do: "Freigabe abgelaufen",
      else: "Freigabe bis #{Format.date(connection.valid_until)}"
  end

  defp last_fetch_text(%{last_sync_at: nil}), do: "noch nicht abgerufen"
  defp last_fetch_text(%{last_sync_at: at}), do: "abgerufen #{Format.datetime(at)}"

  defp trigger_text(:scheduled), do: "planmäßig"
  defp trigger_text(:manual), do: "von Hand"

  defp run_text(%{error: error}) when is_binary(error), do: "fehlgeschlagen: #{error}"
  defp run_text(run), do: counts_text(run)

  defp counts_text(%{new: 0, matched: 0}), do: "nichts Neues"

  defp counts_text(%{new: new, matched: matched}),
    do:
      join_meta([
        ImportSync.new_label(new),
        matched > 0 && ImportSync.matched_label(matched)
      ])

  # The account a bank account feeds stays selectable once it takes no entries, so that only choosing unlinks it.
  defp account_options(accounts, linked) do
    options = Enum.map(accounts, &{&1.name, &1.id})

    case linked.account do
      %Account{} = account ->
        if Enum.any?(accounts, &(&1.id == account.id)),
          do: options,
          else: options ++ [{unoffered_label(account), account.id}]

      nil ->
        options
    end
  end

  defp unoffered_label(%Account{closed: true, name: name}), do: "#{name} (geschlossen)"
  defp unoffered_label(%Account{name: name}), do: "#{name} (nimmt keine Bankumsätze)"

  defp format_iban(nil), do: nil

  defp format_iban(iban),
    do: iban |> String.graphemes() |> Enum.chunk_every(4) |> Enum.map_join(" ", &Enum.join/1)

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    available = BankSync.available?()

    socket =
      assign(socket,
        page_title: "Import & Sync",
        available: available,
        redirect_url: url(~p"/budget/bank-connections/callback"),
        countries: @countries,
        country: "DE",
        bank: nil,
        banks: nil,
        connections: if(available, do: BankSync.list_connections(scope), else: []),
        accounts: [],
        connection: nil,
        links: %{},
        fetching: %{},
        psu: psu(socket)
      )

    {:ok, if(available and connected?(socket), do: load_banks(socket, "DE"), else: socket)}
  end

  # Read at mount, the only time the socket's connect info is there.
  defp psu(socket) do
    x_headers = get_connect_info(socket, :x_headers) || []

    ip =
      Access.client_ip(
        peer_address(get_connect_info(socket, :peer_data)),
        for({"x-forwarded-for", value} <- x_headers, do: value),
        Enum.find_value(x_headers, fn {name, value} -> name == "x-real-ip" && value end),
        Application.fetch_env!(:abakus, :mcp)[:trusted_proxies]
      )

    if ip,
      do: %{ip_address: Access.format(ip), user_agent: get_connect_info(socket, :user_agent)}
  end

  defp peer_address(%{address: address}), do: address
  defp peer_address(_unknown), do: nil

  @impl true
  def handle_params(%{"id" => id}, _uri, %{assigns: %{live_action: :accounts}} = socket) do
    with true <- socket.assigns.available,
         {:ok, id} <- Abakus.Schema.cast_id(id) do
      scope = socket.assigns.current_scope
      connection = BankSync.get_connection!(scope, id)

      {:noreply,
       assign(socket,
         connection: connection,
         links: links(connection),
         accounts: BankSync.accounts(scope)
       )}
    else
      false -> {:noreply, socket}
      :error -> raise NotFoundError
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, connection: nil, links: %{})}

  defp links(connection),
    do:
      Map.new(
        connection.linked_accounts,
        &{&1.id, %{account_id: &1.account_id, start_date: &1.start_date}}
      )

  defp load_banks(socket, country) do
    scope = socket.assigns.current_scope

    socket
    |> assign(country: country, bank: nil, banks: nil)
    |> start_async(:banks, fn -> BankSync.banks(scope, country) end)
  end

  @impl true
  def handle_async(:banks, {:ok, {:ok, banks}}, socket),
    do: {:noreply, assign(socket, :banks, {:ok, banks})}

  def handle_async(:banks, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, :banks, {:error, BankSync.error_message(reason)})}

  def handle_async(:banks, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, :banks, {:error, "Die Banken ließen sich nicht laden."})}

  def handle_async({:fetch, id}, result, socket) do
    {bank_name, fetching} = Map.pop(socket.assigns.fetching, id)

    {:noreply,
     socket
     |> assign(
       fetching: fetching,
       connections: BankSync.list_connections(socket.assigns.current_scope)
     )
     |> fetched(bank_name, result)}
  end

  defp fetched(socket, bank_name, {:ok, {:ok, run}}),
    do: put_flash(socket, :info, "#{bank_name} abgerufen: #{counts_text(run)}.")

  defp fetched(socket, bank_name, {:ok, {:error, message}}),
    do: put_flash(socket, :error, "Abruf von #{bank_name} fehlgeschlagen. #{message}")

  defp fetched(socket, bank_name, {:exit, _reason}),
    do: put_flash(socket, :error, "Abruf von #{bank_name} fehlgeschlagen.")

  @impl true
  def handle_event("change_connect", %{"country" => country} = params, socket) do
    cond do
      country != socket.assigns.country and Map.has_key?(@country_names, country) ->
        {:noreply, load_banks(socket, country)}

      bank = offered_bank(socket.assigns.banks, params["bank"]) ->
        {:noreply, assign(socket, :bank, bank)}

      true ->
        {:noreply, assign(socket, :bank, nil)}
    end
  end

  def handle_event("connect", %{"country" => country, "bank" => bank}, socket) do
    scope = socket.assigns.current_scope
    redirect_url = socket.assigns.redirect_url

    case BankSync.authorize(scope, %{name: bank, country: country}, redirect_url) do
      {:ok, %{url: url, auth: auth}} ->
        {:noreply,
         redirect(socket, to: BankConnectionController.authorize_path(scope, url, auth))}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Nicht verbunden: #{BankSync.error_message(reason)}")}
    end
  end

  def handle_event("connect", _params, socket), do: {:noreply, socket}

  def handle_event("renew", %{"id" => id}, socket) do
    %{current_scope: scope, redirect_url: redirect_url} = socket.assigns

    with {:ok, id} <- Abakus.Schema.cast_id(id),
         %{} = connection <- Enum.find(socket.assigns.connections, &(&1.id == id)) do
      case BankSync.renew(scope, connection, redirect_url) do
        {:ok, %{url: url, auth: auth}} ->
          {:noreply,
           redirect(socket, to: BankConnectionController.authorize_path(scope, url, auth))}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Nicht erneuert: #{BankSync.error_message(reason)}")}
      end
    else
      _missing -> {:noreply, socket}
    end
  end

  def handle_event("change_links", params, socket),
    do: {:noreply, assign(socket, :links, changed_links(socket, params["links"] || %{}))}

  def handle_event("save_links", params, socket) do
    links = changed_links(socket, params["links"] || %{})

    case BankSync.assign_accounts(socket.assigns.current_scope, socket.assigns.connection, links) do
      {:ok, _connection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Konten zugeordnet.")
         |> push_navigate(to: ~p"/budget/bank-connections")}

      {:error, message} ->
        {:noreply, socket |> assign(:links, links) |> put_flash(:error, message)}
    end
  end

  def handle_event("fetch", %{"id" => id}, socket) do
    %{current_scope: scope, psu: psu, fetching: fetching} = socket.assigns

    with {:ok, id} <- Abakus.Schema.cast_id(id),
         false <- Map.has_key?(fetching, id),
         %{} = connection <- Enum.find(socket.assigns.connections, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(:fetching, Map.put(fetching, id, connection.bank_name))
       |> start_async({:fetch, id}, fn -> BankSync.fetch(scope, connection, psu: psu) end)}
    else
      _running_or_missing -> {:noreply, socket}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, id} <- Abakus.Schema.cast_id(id),
         %{} = connection <- Enum.find(socket.assigns.connections, &(&1.id == id)) do
      {:ok, _connection} = BankSync.delete_connection(scope, connection)

      {:noreply,
       socket
       |> assign(:connections, BankSync.list_connections(scope))
       |> put_flash(:info, "#{connection.bank_name} ist getrennt.")
       |> push_patch(to: ~p"/budget/bank-connections")}
    else
      _missing -> {:noreply, socket}
    end
  end

  defp offered_bank({:ok, banks}, name) when is_binary(name),
    do: if(Enum.any?(banks, &(&1.name == name)), do: name)

  defp offered_bank(_banks, _name), do: nil

  # An account chosen anew gets its own start date, so a date typed for another account goes.
  defp changed_links(socket, params) do
    %{accounts: accounts, connection: connection, links: links, current_scope: scope} =
      socket.assigns

    offered = Map.new(accounts, &{&1.id, &1})

    Map.new(connection.linked_accounts, fn linked ->
      case params[Integer.to_string(linked.id)] do
        nil ->
          {linked.id, links[linked.id]}

        row ->
          {linked.id, changed_link(scope, links[linked.id], row, selectable(offered, linked))}
      end
    end)
  end

  defp selectable(offered, %{account: nil}), do: offered
  defp selectable(offered, %{account: account}), do: Map.put_new(offered, account.id, account)

  defp changed_link(scope, link, row, accounts) do
    account = accounts[parse_id(row["account_id"])]

    cond do
      account == nil ->
        %{account_id: nil, start_date: nil}

      account.id != link.account_id ->
        %{account_id: account.id, start_date: BankSync.start_date(scope, account)}

      true ->
        %{link | start_date: parse_date(row["start_date"])}
    end
  end

  defp parse_id(text) when is_binary(text) do
    case Abakus.Ids.cast(text) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp parse_id(_missing), do: nil

  defp parse_date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_missing), do: nil
end

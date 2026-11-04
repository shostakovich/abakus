defmodule AbakusWeb.Depot.SecuritiesLive do
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{MarketData, Securities, Settings}
  alias Abakus.{ExchangeRates, Format, LocalTime}
  alias AbakusWeb.Depot.Format, as: DepotFormat
  alias AbakusWeb.Depot.{NewSecurity, SecurityDialog, SecurityRow}

  @unknown_benchmark "Dieses Wertpapier gibt es nicht mehr, die Benchmark bleibt."
  @gone "Dieses Wertpapier gibt es nicht mehr."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, today: LocalTime.today())

    ~H"""
    <Layouts.depot
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@depot_sidebar}
      expiring_consents={@expiring_consents}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={{:depots, nil}}
    >
      <.depots_header tab={:securities}>
        <:subtitle>{subtitle(@active, @retired)}</:subtitle>
        <:actions>
          <.button
            id="security-add"
            icon="plus"
            class="max-sm:hidden"
            patch={~p"/depot/securities/new"}
          >
            Wertpapier hinzufügen
          </.button>
        </:actions>
      </.depots_header>

      <.empty_state :if={@active == [] and @retired == []} plush="layers" icon="layers">
        Noch keine Wertpapiere.
      </.empty_state>

      <.table
        :if={@active != [] or @retired != []}
        id="securities"
        rows={@active}
        groups={groups(@active, @retired)}
        row_id={&"security-#{&1.id}"}
        row_link={&~p"/depot/securities/#{&1}"}
        row_attrs={&row_attrs/1}
        actions_show_from={:sm}
      >
        <:col :let={security} label="Wertpapier" class="w-full max-w-0">
          <span class="line-clamp-2">{security.name}</span>
          <.cell_sub :if={security.isin || security.id == @benchmark_id} show_from={:lg}>
            <.isin_line isin={security.isin} benchmark={security.id == @benchmark_id} />
          </.cell_sub>
          <.cell_sub hide_from={:lg} class="truncate">
            <.sub_line
              security={security}
              marks={SecurityRow.marks(security, @benchmark_id, @divvy_diary)}
              today={@today}
            />
          </.cell_sub>
        </:col>
        <:col
          :let={security}
          label="Kursquelle"
          show_from={:lg}
          class="whitespace-nowrap text-base-content/70"
        >
          {SecurityRow.source(security)}
        </:col>
        <:col :let={security} label="Kurs" align={:end}>
          <.price security={security} />
        </:col>
        <:col :let={security} label="Stand" align={:end} show_from={:sm}>
          {SecurityRow.quote_date(security, @today) || "–"}
        </:col>
        <:col :let={security} label="Hinweise" hide_label show_from={:lg} class="whitespace-nowrap">
          <.marks
            security={security}
            marks={SecurityRow.marks(security, @benchmark_id, @divvy_diary)}
          />
        </:col>
        <:action
          label={&"#{&1.name} bearbeiten"}
          icon="pencil"
          id={&"security-#{&1.id}-edit"}
          patch={&~p"/depot/securities/#{&1}/edit"}
        />
      </.table>

      <div class="mt-4 sm:hidden">
        <.button id="security-add-below" icon="plus" patch={~p"/depot/securities/new"}>
          Wertpapier hinzufügen
        </.button>
      </div>

      <div class="mt-8 grid gap-x-12 gap-y-8 lg:grid-cols-2">
        <section id="benchmark" aria-labelledby="benchmark-title">
          <.section_heading id="benchmark-title">Benchmark</.section_heading>
          <.form
            for={@benchmark_form}
            id="benchmark-form"
            phx-change="save_benchmark"
            phx-submit="save_benchmark"
          >
            <.input
              field={@benchmark_form[:benchmark_id]}
              type="select"
              label="Vergleichen mit"
              options={benchmark_options(@active, @benchmark)}
            />
          </.form>
          <p class="text-sm text-base-content/70">
            Zum Vergleich in <.link navigate={~p"/depot"} class="link">Vermögen</.link>
            und <.link navigate={depots_path(:performance)} class="link">Performance</.link>.
          </p>
        </section>

        <section id="data-sources" aria-labelledby="data-sources-title">
          <.section_heading id="data-sources-title">Datenquellen</.section_heading>
          <.description_list>
            <:item label="Kurse">
              <p class="font-normal">Yahoo<.meta_sep />täglich 18:00</p>
              <p class="font-normal text-base-content/70">{last_run(@prices_run)}</p>
            </:item>
            <:item label="Fondsdaten">
              <p class="font-normal">DivvyDiary<.meta_sep />täglich mit den Kursen</p>
              <p class="font-normal text-base-content/70">
                {if @divvy_diary, do: last_asked(@prices_run), else: "ohne API-Key keine Fondsdaten"}
              </p>
            </:item>
            <:item label="Wechselkurse">
              <p class="font-normal">EZB<.meta_sep />täglich 17:00</p>
              <p :if={@rates_run && @rates_run.error} class="font-normal text-error-ink">
                {@rates_run.error}
              </p>
              <p class="font-normal text-base-content/70">
                {if @rates_until, do: "bis #{Format.date(@rates_until)}", else: "noch keine"}
              </p>
            </:item>
          </.description_list>
        </section>
      </div>

      <.add_dialog :if={@add} add={@add} />
      <.live_component
        :if={@editing}
        module={SecurityDialog}
        id="security-dialog"
        security={@editing}
        params={@edit_params}
        current_scope={@current_scope}
        return_to={~p"/depot/securities"}
        deleted_to={~p"/depot/securities"}
      />
    </Layouts.depot>
    """
  end

  defp groups(_active, []), do: nil

  defp groups(active, retired) do
    [
      active != [] && %{id: "active", label: nil, rows: active},
      %{id: "retired", label: "Ausgemustert", rows: retired, fold: :closed}
    ]
    |> Enum.filter(& &1)
  end

  defp row_attrs(%{retired: true}), do: %{class: "text-base-content/70"}
  defp row_attrs(_security), do: nil

  attr :security, :map, required: true

  defp price(assigns) do
    ~H"""
    <.amount
      value={@security.latest_close}
      placeholder="–"
      currency={@security.currency}
      currency_display={DepotFormat.currency_display(@security.currency)}
      minor_digits={8}
      decimals={2..4}
      pad_decimals={4}
    />
    """
  end

  attr :isin, :string, required: true
  attr :benchmark, :boolean, required: true

  defp isin_line(assigns) do
    ~H"""
    <.identifier :if={@isin}>{@isin}</.identifier><span :if={@benchmark}><.meta_sep :if={@isin} /><.benchmark_mark /></span>
    """
  end

  defp benchmark_mark(assigns) do
    ~H"""
    <.badge tone={:primary} style={:text}>Benchmark</.badge>
    """
  end

  attr :security, :map, required: true
  attr :marks, :list, required: true
  attr :today, Date, required: true

  defp sub_line(assigns) do
    marks = assigns.marks

    assigns =
      assign(assigns,
        error?: Enum.any?(marks, &match?({:error, _}, &1)),
        no_isin?: :no_isin in marks,
        benchmark?: :benchmark in marks,
        date: SecurityRow.quote_date(assigns.security, assigns.today)
      )

    ~H"""
    <span :if={@error?} class="text-error-ink">
      <.icon name="circle-alert" class="size-3.5 align-[-2px]" /><span class="sr-only">Fehler</span>
    </span>
    {SecurityRow.short_source(@security)}<span :if={@date} class="sm:hidden"><.meta_sep />{@date}</span><span :if={
      @no_isin?
    }><.meta_sep /><.badge
      tone={:warning}
      style={:text}
    >
      ISIN fehlt
    </.badge></span><span :if={@benchmark?}><.meta_sep /><.benchmark_mark /></span>
    """
  end

  attr :security, :map, required: true
  attr :marks, :list, required: true

  defp marks(assigns) do
    assigns = assign(assigns, :errors, for({:error, message} <- assigns.marks, do: message))

    ~H"""
    <div class="relative z-10 flex items-center justify-end gap-3">
      <.link
        :if={@errors != []}
        id={"security-#{@security.id}-error"}
        patch={~p"/depot/securities/#{@security}/edit"}
        class="rounded-field hover:underline"
        aria-label={"Fehler bei #{@security.name} ansehen"}
      >
        <.badge tone={:error} style={:text}>Fehler</.badge>
      </.link>
      <.badge
        :if={:no_fund_data in @marks}
        id={"security-#{@security.id}-no-fund-data"}
        style={:text}
        class="text-base-content/70"
      >
        Keine Fondsdaten
      </.badge>
      <.badge :if={:no_isin in @marks} tone={:warning} style={:text}>ISIN fehlt</.badge>
    </div>
    """
  end

  attr :add, :map, required: true

  defp add_dialog(assigns) do
    new_security = assigns.add.new_security
    assigns = assign(assigns, form: new_security.form, existing: new_security.existing)

    ~H"""
    <.modal
      id="new-security-dialog"
      show
      title="Wertpapier hinzufügen"
      placement={:top}
      on_cancel={JS.patch(~p"/depot/securities")}
    >
      <.segmented
        id="new-security-by"
        mode={:button}
        label="Hinzufügen per"
        value={@add.by}
        block
        class="mb-2"
        phx-click="add_by"
        options={[{"ISIN", "isin"}, {"Yahoo-Symbol", "symbol"}]}
      />
      <.form
        for={@form}
        id="new-security-form"
        class={@add.by != "isin" && "hidden"}
        phx-change="validate_new"
        phx-submit="create"
      >
        <.input
          field={@form[:isin]}
          label="ISIN"
          identifier
          size="13"
          placeholder="XX0000000000"
          phx-debounce="300"
          phx-blur="leave_isin"
          autofocus
          help={!@existing && NewSecurity.lookup_text(@add.new_security)}
        />
        <.alert :if={@existing} id="new-security-existing" class="my-2">
          {if @existing.retired, do: "Gibt es schon, ausgemustert:", else: "Gibt es schon:"} {@existing.name}
          <:actions>
            <.button patch={existing_path(@existing)} size={:sm}>
              {if @existing.retired, do: "Wieder aufnehmen", else: "Bearbeiten"}
            </.button>
          </:actions>
        </.alert>
        <div id="new-security-fields" class={@existing && "hidden"}>
          <.input field={@form[:name]} label="Name" autocomplete="off" />
          <.input
            field={@form[:symbol]}
            label="Yahoo-Symbol"
            placeholder="XYZ.DE"
            autocomplete="off"
            spellcheck="false"
            autocapitalize="characters"
            help="Leer lassen ohne Kurse von Yahoo."
          />
        </div>
        <.action_bar class="mt-4">
          <.button patch={~p"/depot/securities"}>Abbrechen</.button>
          <.button
            id="new-security-create"
            type="submit"
            variant={:primary}
            disabled={@existing != nil}
            phx-disable-with="Legt an …"
          >
            Hinzufügen
          </.button>
        </.action_bar>
      </.form>
      <.form
        for={@add.symbol_form}
        id="yahoo-security-form"
        class={@add.by != "symbol" && "hidden"}
        phx-submit="create_by_symbol"
      >
        <.alert :if={@add.retired_symbol} id="yahoo-security-existing" class="my-2">
          Gibt es schon, ausgemustert: {@add.retired_symbol.name}
          <:actions>
            <.button patch={existing_path(@add.retired_symbol)} size={:sm}>
              Wieder aufnehmen
            </.button>
          </:actions>
        </.alert>
        <.input
          field={@add.symbol_form[:symbol]}
          label="Yahoo-Symbol"
          placeholder="XYZ.DE"
          autocomplete="off"
          spellcheck="false"
          autocapitalize="characters"
          help="Name, Währung und Kurse kommen von Yahoo. Ohne ISIN gibt es keine Fondsdaten; die ISIN lässt sich später ergänzen."
        />
        <.action_bar class="mt-4">
          <.button patch={~p"/depot/securities"}>Abbrechen</.button>
          <.button
            id="yahoo-security-create"
            type="submit"
            variant={:primary}
            phx-disable-with="Wird abgerufen …"
          >
            Hinzufügen
          </.button>
        </.action_bar>
      </.form>
    </.modal>
    """
  end

  defp existing_path(%{retired: true} = security),
    do: ~p"/depot/securities/#{security}/edit?reactivate"

  defp existing_path(security), do: ~p"/depot/securities/#{security}/edit"

  defp last_run(nil), do: "noch nicht abgerufen"
  defp last_run(run), do: "zuletzt #{Format.recent(run.ran_at)}"

  defp last_asked(nil), do: "noch nicht gefragt"
  defp last_asked(run), do: "zuletzt gefragt #{Format.recent(run.ran_at)}"

  defp subtitle(active, retired) do
    join_meta([
      count(length(active), "1 Wertpapier", "Wertpapiere"),
      retired != [] && "#{Format.number(length(retired))} ausgemustert"
    ])
  end

  defp count(0, _one, many), do: "keine #{many}"
  defp count(1, one, _many), do: one
  defp count(count, _one, many), do: "#{Format.number(count)} #{many}"

  # The active securities, and the benchmark even once it is retired.
  defp benchmark_options(active, benchmark) do
    securities = if benchmark in [nil | active], do: active, else: active ++ [benchmark]
    [{"Keine Benchmark", ""} | Enum.map(securities, &{&1.name, &1.id})]
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Wertpapiere",
       add: nil,
       editing: nil,
       edit_params: %{},
       divvy_diary: MarketData.divvy_diary_available?()
     )}
  end

  # The list loads once, and again on the way back from a dialog.
  @impl true
  def handle_params(params, _uri, socket) do
    socket = open(socket, socket.assigns.live_action, params)
    loaded? = Map.has_key?(socket.assigns, :active) and socket.assigns.live_action != :index
    {:noreply, if(loaded?, do: socket, else: load(socket))}
  end

  defp open(socket, :index, _params), do: assign(socket, add: nil, editing: nil)

  defp open(socket, :new, _params) do
    add = %{
      by: "isin",
      new_security: NewSecurity.new(),
      symbol_form: symbol_form(),
      retired_symbol: nil
    }

    assign(socket, add: add, editing: nil)
  end

  defp open(socket, :edit, %{"id" => id} = params) do
    case parse_id(id) && Securities.get_security(socket.assigns.current_scope, parse_id(id)) do
      nil ->
        socket |> put_flash(:error, @gone) |> push_patch(to: ~p"/depot/securities")

      security ->
        edit_params =
          if Map.has_key?(params, "reactivate"), do: %{"retired" => "false"}, else: %{}

        assign(socket, add: nil, editing: security, edit_params: edit_params)
    end
  end

  defp symbol_form(changeset \\ Securities.change_yahoo_symbol()),
    do: to_form(changeset, as: :yahoo)

  defp load(socket) do
    scope = socket.assigns.current_scope
    {retired, active} = scope |> Securities.list_securities() |> Enum.split_with(& &1.retired)
    benchmark_id = Settings.benchmark_id(scope)
    benchmark = Enum.find(active ++ retired, &(&1.id == benchmark_id))

    editing =
      socket.assigns.editing &&
        Enum.find(active ++ retired, &(&1.id == socket.assigns.editing.id))

    socket
    |> assign(active: active, retired: retired, benchmark_id: benchmark_id, benchmark: benchmark)
    |> assign(:benchmark_form, to_form(%{"benchmark_id" => benchmark_id}, as: :benchmark))
    |> assign(rates_until: ExchangeRates.last_date(), rates_run: ExchangeRates.last_run())
    |> assign(:prices_run, MarketData.last_run())
    |> assign(:editing, editing)
  end

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load(socket)}

  # Saving patches back to the list, which loads it.
  def handle_info({SecurityDialog, :saved}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save_benchmark", %{"benchmark" => %{"benchmark_id" => id}}, socket) do
    with {:ok, security_id} <- benchmark_id(id),
         {:ok, _setting} <- Settings.update_benchmark(socket.assigns.current_scope, security_id) do
      socket = load(socket)
      {:noreply, put_flash(socket, :info, benchmark_message(socket.assigns.benchmark))}
    else
      _error -> {:noreply, socket |> load() |> put_flash(:error, @unknown_benchmark)}
    end
  end

  def handle_event("add_by", %{"value" => by}, %{assigns: %{add: %{} = add}} = socket)
      when by in ["isin", "symbol"],
      do: {:noreply, assign(socket, :add, %{add | by: by})}

  def handle_event("validate_new", %{"security" => params} = event, socket) do
    %{add: add, current_scope: scope} = socket.assigns

    case NewSecurity.change(scope, add.new_security, params, event["_target"]) do
      {:lookup, new_security, isin} ->
        socket
        |> assign(:add, %{add | new_security: new_security})
        |> start_async(:lookup, fn -> NewSecurity.lookup(isin) end)
        |> then(&{:noreply, &1})

      {:ok, new_security} ->
        {:noreply, assign(socket, :add, %{add | new_security: new_security})}
    end
  end

  def handle_event("leave_isin", _params, %{assigns: %{add: %{} = add}} = socket),
    do:
      {:noreply,
       assign(socket, :add, %{add | new_security: NewSecurity.leave_isin(add.new_security)})}

  def handle_event("leave_isin", _params, socket), do: {:noreply, socket}

  def handle_event("create", _params, %{assigns: %{add: %{} = add}} = socket) do
    case NewSecurity.create(socket.assigns.current_scope, add.new_security) do
      {:ok, security} ->
        {:noreply, done(socket, created_message(security, socket.assigns.divvy_diary))}

      {:error, new_security} ->
        {:noreply, assign(socket, :add, %{add | new_security: new_security})}
    end
  end

  def handle_event("create_by_symbol", %{"yahoo" => params}, %{assigns: %{add: add}} = socket) do
    known = MapSet.new(socket.assigns.active, & &1.id)

    case MarketData.create_yahoo_security(socket.assigns.current_scope, params) do
      {:ok, %{retired: true} = security} ->
        {:noreply, assign(socket, :add, %{add | retired_symbol: security})}

      {:ok, security} ->
        message =
          if security.id in known,
            do: "„#{security.name}“ gibt es schon.",
            else: "„#{security.name}“ hinzugefügt."

        {:noreply, done(socket, message)}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :add, %{add | symbol_form: symbol_form(changeset), retired_symbol: nil})}
    end
  end

  @impl true
  def handle_async(:lookup, result, %{assigns: %{add: %{} = add}} = socket) do
    new_security = NewSecurity.looked_up(add.new_security, result)
    {:noreply, assign(socket, :add, %{add | new_security: new_security})}
  end

  def handle_async(:lookup, _result, socket), do: {:noreply, socket}

  defp done(socket, message) do
    socket
    |> put_flash(:info, message)
    |> push_patch(to: ~p"/depot/securities")
  end

  defp created_message(security, divvy_diary?) do
    if divvy_diary? and security.isin,
      do: "„#{security.name}“ hinzugefügt. DivvyDiary wird gefragt …",
      else: "„#{security.name}“ hinzugefügt."
  end

  defp benchmark_message(nil), do: "Keine Benchmark mehr."

  defp benchmark_message(security),
    do: "Vermögen und Performance vergleichen mit #{security.name}."

  defp benchmark_id(""), do: {:ok, nil}

  defp benchmark_id(id) do
    case parse_id(id) do
      nil -> :error
      security_id -> {:ok, security_id}
    end
  end
end

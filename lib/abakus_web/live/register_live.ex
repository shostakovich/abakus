defmodule AbakusWeb.RegisterLive do
  @moduledoc """
  The register: one account's transactions (`/accounts/:id`) or every account's (`/accounts/all`), newest first,
  below the balances. The view (`filter`), the search (`q`) and the running balance (`running`, one account in the
  full list only) live in the URL; the selection does not.

  Here transactions are approved (one, the selected or all), categorised (the selected), flagged and toggled
  between uncleared and cleared. A change to a reconciled transaction asks in the browser first and then sends
  `reconciled: "confirmed"`, which goes to the Ledger as `reconciled: :confirmed`. Match proposals are not in the
  register, so approving all leaves them open. Accounts fed by another app offer no manual entry.
  """
  use AbakusWeb, :live_view

  alias Abakus.{Categories, Ledger}
  alias AbakusWeb.AccountGroups
  alias AbakusWeb.RegisterLive.{Balances, Components, Rows}
  alias Plug.Conn.Query

  @flags Ecto.Enum.dump_values(Abakus.Ledger.Transaction, :flag)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={:accounts}
      account_id={@account && @account.id}
      account_groups={@account_groups}
    >
      <div id="register">
        <Components.banner
          :if={@unapproved != []}
          transactions={@unapproved}
          show_path={@filter != :unapproved && @paths.filters.unapproved}
        />
        <.link
          navigate={~p"/accounts"}
          class="d-inline-flex d-lg-none align-items-center gap-1 small mb-1"
        >
          <.icon name="back" class="app-icon-sm" /> Konten
        </.link>
        <div class="d-flex align-items-center gap-2">
          <h1 id="register-title" class="h3 mb-0 flex-grow-1 text-truncate">{@page_title}</h1>
          <.link
            :if={@account}
            navigate={~p"/accounts/#{@account}/edit"}
            class="btn btn-sm btn-light"
            aria-label="Konto bearbeiten"
            title="Konto bearbeiten"
          >
            <.icon name="pencil" class="app-icon-sm" />
          </.link>
        </div>
        <Components.meta account={@account} />
        <Components.balances account={@account} balances={@balances} />
        <Components.toolbar
          account={@account}
          filter={@filter}
          query={@query}
          running={@running}
          running_shown={@running_balances != nil}
          paths={@paths}
        />
        <Components.bulk
          :if={MapSet.size(@selected) > 0}
          selected={Enum.filter(@rows, &(&1.id in @selected))}
          categories={@categories}
        />
        <Components.table
          rows={@rows}
          accounts={@accounts}
          all={is_nil(@account)}
          selected={@selected}
          flag_menu={@flag_menu}
          running={@running_balances}
          empty={empty_text(@transactions)}
        />
        <Components.cards
          rows={@rows}
          accounts={@accounts}
          all={is_nil(@account)}
          empty={empty_text(@transactions)}
        />
        <Components.legend :if={!(@account && @account.fed_by == :portfolio)} />
      </div>
    </Layouts.app>
    """
  end

  defp empty_text([]), do: "Noch keine Buchungen."
  defp empty_text(_transactions), do: "Keine Buchungen in dieser Ansicht."

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       categories: category_options(),
       scope: nil,
       selected: MapSet.new(),
       flag_menu: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(
       filter: filter(params["filter"]),
       query: params["q"] || "",
       running: params["running"] == "1"
     )
     |> load(scope(socket.assigns.live_action, params))
     |> assign_rows()}
  end

  defp scope(:all, _params), do: :all
  defp scope(:show, %{"id" => id}), do: {:account, id}

  defp load(%{assigns: %{scope: scope}} = socket, scope), do: socket

  defp load(socket, :all) do
    socket
    |> assign(scope: :all, account: nil, page_title: "Alle Konten", selected: MapSet.new())
    |> load_transactions()
  end

  defp load(socket, {:account, id} = scope) do
    account = Ledger.get_account!(id)

    socket
    |> assign(scope: scope, account: account, page_title: account.name, selected: MapSet.new())
    |> load_transactions()
  end

  defp load_transactions(socket),
    do: assign(socket, :transactions, Ledger.list_transactions(socket.assigns.account || :all))

  defp assign_rows(socket) do
    %{transactions: transactions, filter: filter, query: query} = socket.assigns
    account_rows = AccountGroups.rows(socket.assigns.account_groups)
    rows = transactions |> Rows.filter(filter) |> Rows.search(query)
    balances = balances(socket.assigns.account, account_rows)

    assign(socket,
      rows: rows,
      accounts: Map.new(account_rows, &{&1.account.id, &1.account}),
      balances: balances,
      unapproved: Enum.reject(transactions, & &1.approved),
      running_balances: running_balances(socket.assigns, rows, balances),
      paths: view_paths(socket.assigns),
      selected: MapSet.intersection(socket.assigns.selected, MapSet.new(rows, & &1.id))
    )
  end

  defp balances(nil, account_rows), do: Balances.all(account_rows)

  defp balances(account, account_rows),
    do: account_rows |> Enum.find(&(&1.account.id == account.id)) |> Balances.account()

  # Only one account's full list adds up to its balance.
  defp running_balances(
         %{account: account, running: true, filter: :all, query: query},
         rows,
         balances
       )
       when not is_nil(account) do
    if String.trim(query) == "", do: Rows.running(rows, balances.working)
  end

  defp running_balances(_assigns, _rows, _balances), do: nil

  @impl true
  def handle_event("search", %{"q" => query}, socket),
    do: {:noreply, push_patch(socket, to: register_path(socket.assigns, q: query))}

  def handle_event("toggle_cleared", %{"id" => id} = params, socket) do
    change(socket, id, fn transaction ->
      Ledger.update_transaction(
        transaction,
        %{cleared: toggled(transaction.cleared)},
        confirmed(params)
      )
    end)
  end

  def handle_event("approve", %{"id" => id} = params, socket) do
    change(socket, id, &Ledger.update_transaction(&1, %{approved: true}, confirmed(params)))
  end

  def handle_event("approve_all", params, socket),
    do: approve(socket, socket.assigns.unapproved, params)

  # The selection stays until it is approved.
  def handle_event("approve_selected", params, socket) do
    case Enum.reject(selected(socket.assigns), & &1.approved) do
      [] ->
        {:noreply,
         put_flash(socket, :info, "Keine der ausgewählten Buchungen wartet auf Bestätigung.")}

      waiting ->
        approve(socket, waiting, params, &assign(&1, :selected, MapSet.new()))
    end
  end

  def handle_event("categorise_selected", %{"category_id" => id} = params, socket) do
    case Enum.find(category_ids(socket.assigns.categories), &(Integer.to_string(&1) == id)) do
      nil -> {:noreply, socket}
      category_id -> categorise(socket, category_id, params)
    end
  end

  def handle_event("select", %{"id" => id}, socket) do
    case find(socket, id) do
      nil -> {:noreply, socket}
      transaction -> {:noreply, update(socket, :selected, &toggle(&1, transaction.id))}
    end
  end

  def handle_event("select_all", _params, socket) do
    shown = MapSet.new(socket.assigns.rows, & &1.id)
    selected = if MapSet.equal?(socket.assigns.selected, shown), do: MapSet.new(), else: shown
    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("clear_selection", _params, socket),
    do: {:noreply, assign(socket, :selected, MapSet.new())}

  def handle_event("flag_menu", %{"id" => id}, socket) do
    case find(socket, id) do
      nil -> {:noreply, socket}
      %{id: id} when id == socket.assigns.flag_menu -> {:noreply, assign(socket, :flag_menu, nil)}
      transaction -> {:noreply, assign(socket, :flag_menu, transaction.id)}
    end
  end

  def handle_event("close_flag_menu", _params, socket),
    do: {:noreply, assign(socket, :flag_menu, nil)}

  def handle_event("set_flag", %{"id" => id, "flag" => flag} = params, socket)
      when flag in ["" | @flags] do
    socket
    |> assign(:flag_menu, nil)
    |> change(id, &Ledger.update_transaction(&1, %{flag: blank_to_nil(flag)}, confirmed(params)))
  end

  # A reconciled transaction is unlocked to cleared, so the cleared balance stays as it is.
  defp toggled(:uncleared), do: :cleared
  defp toggled(:cleared), do: :uncleared
  defp toggled(:reconciled), do: :cleared

  defp confirmed(%{"reconciled" => "confirmed"}), do: [reconciled: :confirmed]
  defp confirmed(_params), do: []

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(flag), do: flag

  defp toggle(set, id), do: if(id in set, do: MapSet.delete(set, id), else: MapSet.put(set, id))

  defp change(socket, id, fun) do
    case find(socket, id) do
      nil -> {:noreply, socket}
      transaction -> socket |> saved(fun.(transaction)) |> noreply()
    end
  end

  defp approve(socket, transactions, params, approved \\ & &1) do
    result = Ledger.update_transactions(transactions, %{approved: true}, confirmed(params))
    socket = if match?({:ok, _}, result), do: approved.(socket), else: socket
    socket |> saved(result, "#{length(transactions)} bestätigt.") |> noreply()
  end

  defp categorise(socket, category_id, params) do
    case Enum.filter(selected(socket.assigns), &Rows.categorisable?(&1, socket.assigns.accounts)) do
      [] ->
        {:noreply,
         put_flash(socket, :error, "Keine der ausgewählten Buchungen nimmt eine Kategorie.")}

      transactions ->
        result =
          Ledger.update_transactions(transactions, %{category_id: category_id}, confirmed(params))

        socket |> saved(result, "#{length(transactions)} kategorisiert.") |> noreply()
    end
  end

  defp saved(socket, result, message \\ nil)

  defp saved(socket, {:ok, _changed}, message) do
    socket
    |> clear_flash()
    |> then(&if(message, do: put_flash(&1, :info, message), else: &1))
    |> refresh()
  end

  defp saved(socket, {:error, changeset}, _message),
    do: socket |> put_flash(:error, "Nicht geändert: #{errors(changeset)}") |> refresh()

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Map.values()
    |> List.flatten()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp refresh(socket) do
    socket
    |> assign(:account_groups, AccountGroups.load())
    |> load_transactions()
    |> assign_rows()
  end

  defp noreply(socket), do: {:noreply, socket}

  defp find(socket, id),
    do: Enum.find(socket.assigns.transactions, &(Integer.to_string(&1.id) == id))

  defp selected(assigns), do: Enum.filter(assigns.rows, &(&1.id in assigns.selected))

  defp filter(param), do: Enum.find(Rows.filters(), :all, &(Atom.to_string(&1) == param))

  defp view_paths(assigns) do
    %{
      filters: Map.new(Rows.filters(), &{&1, register_path(assigns, filter: &1)}),
      running: register_path(assigns, running: !assigns.running)
    }
  end

  # The register's URL with the view, search and running balance, changed by `changes`; defaults stay out.
  defp register_path(assigns, changes) do
    current = %{filter: assigns.filter, q: assigns.query, running: assigns.running}
    %{filter: filter, q: query, running: running} = Map.merge(current, Map.new(changes))

    params =
      [
        filter: filter != :all && filter,
        q: String.trim(query) != "" && query,
        running: running && "1"
      ]
      |> Enum.filter(fn {_key, value} -> value end)

    base = if assigns.account, do: ~p"/accounts/#{assigns.account}", else: ~p"/accounts/all"
    if params == [], do: base, else: base <> "?" <> Query.encode(params)
  end

  # Ready to Assign first, then the visible categories by group, as `options_for_select/2` takes them.
  defp category_options do
    ready_to_assign = Categories.ready_to_assign!()

    groups =
      for group <- Categories.list_category_groups(),
          not group.hidden,
          categories = Enum.reject(group.categories, & &1.hidden),
          categories != [] do
        {group.name, Enum.map(categories, &{&1.name, &1.id})}
      end

    [{"Zu verteilen (Einnahme)", ready_to_assign.id} | groups]
  end

  defp category_ids(options) do
    Enum.flat_map(options, fn
      {_group, categories} when is_list(categories) -> Enum.map(categories, &elem(&1, 1))
      {_name, id} -> [id]
    end)
  end
end

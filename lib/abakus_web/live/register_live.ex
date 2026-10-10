defmodule AbakusWeb.RegisterLive do
  @moduledoc """
  The register: one account's transactions (`/accounts/:id`) or every account's (`/accounts/all`), newest first,
  below the balances. The view (`filter`), the search (`q`) and the running balance (`running`, one account in the
  full list only) live in the URL; the selection does not.

  Here transactions are approved (one, the selected or all), categorised (the selected), flagged and toggled
  between uncleared and cleared. A change to a reconciled transaction asks in the browser first and then sends
  `reconciled: "confirmed"`, which goes to the Ledger as `reconciled: :confirmed`. Match proposals are not in the
  register, so approving all leaves them open. Accounts fed by another app offer no manual entry.

  The pencil beside the name opens the account form (`AbakusWeb.AccountDialog`); the account shown is the one in
  `account_groups`, so it is as fresh as the sidebar.

  The transaction form (`TransactionDialog`) opens over the register for a new transaction (`…/transactions/new`)
  or to edit one (`…/transactions/:transaction_id/edit`), keeping the view in the URL. The counterpart of a split's
  transfer opens its split.
  """
  use AbakusWeb, :live_view

  alias Abakus.Ledger
  alias AbakusWeb.{AccountGroups, CategoryOptions, Format}
  alias AbakusWeb.RegisterLive.{Balances, Components, Rows, TransactionDialog}
  alias Plug.Conn.Query

  import TransactionDialog, only: [confirmed: 1]

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
      account_dialog={@account_dialog}
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
          <button
            :if={@account}
            id="edit-account"
            type="button"
            class="btn btn-sm btn-light"
            aria-label="Konto bearbeiten"
            title="Konto bearbeiten"
            phx-click="open_account_dialog"
            phx-value-id={@account.id}
          >
            <.icon name="pencil" class="app-icon-sm" />
          </button>
        </div>
        <Components.meta account={@account} />
        <Components.balances account={@account} balances={@balances} />
        <Components.toolbar
          account={@account}
          new_path={@paths.new}
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
          edit_path={@paths.edit}
          empty={empty_text(@transactions)}
        />
        <Components.cards
          rows={@rows}
          accounts={@accounts}
          all={is_nil(@account)}
          edit_path={@paths.edit}
          empty={empty_text(@transactions)}
        />
        <Components.legend :if={!(@account && @account.fed_by == :portfolio)} />
        <.link
          :if={@paths.new && !@dialog}
          id="new-transaction-fab"
          patch={@paths.new}
          class="btn btn-primary btn-lg rounded-pill shadow-lg d-inline-flex d-md-none align-items-center gap-1 app-fab"
        >
          <.icon name="plus" /> Buchung
        </.link>
      </div>
      <.live_component
        :if={@dialog}
        module={TransactionDialog}
        id="transaction-dialog"
        transaction={@dialog.transaction}
        split_of={@dialog.split_of}
        account={@account}
        accounts={@accounts}
        today={@today}
        return_to={@paths.list}
      />
    </Layouts.app>
    """
  end

  defp empty_text([]), do: "Noch keine Buchungen."
  defp empty_text(_transactions), do: "Keine Buchungen in dieser Ansicht."

  @impl true
  def mount(_params, _session, socket) do
    connect = get_connect_params(socket) || %{}

    {:ok,
     assign(socket,
       today: Format.today(connect["today"]),
       categories: CategoryOptions.build(),
       scope: nil,
       dialog: nil,
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
     |> load(scope(params))
     |> assign_rows()
     |> open_dialog(socket.assigns.live_action, params)}
  end

  defp scope(%{"id" => id}), do: {:account, id}
  defp scope(_params), do: :all

  # With no account taking manual entries there is nothing to book in.
  defp open_dialog(socket, :new, _params) do
    if Enum.any?(Map.values(socket.assigns.accounts), &TransactionDialog.manual?/1),
      do: assign(socket, :dialog, %{transaction: nil, split_of: false}),
      else: socket |> assign(:dialog, nil) |> push_patch(to: socket.assigns.paths.list)
  end

  defp open_dialog(socket, :edit, %{"transaction_id" => id}) do
    case editable(fetch_transaction(id)) do
      {:ok, transaction, split_of} ->
        assign(socket, :dialog, %{transaction: transaction, split_of: split_of})

      :error ->
        socket
        |> assign(:dialog, nil)
        |> put_flash(:error, "Buchung nicht gefunden.")
        |> push_patch(to: socket.assigns.paths.list)
    end
  end

  defp open_dialog(socket, _list, _params), do: assign(socket, :dialog, nil)

  defp fetch_transaction(id) do
    case Integer.parse(id) do
      {id, ""} -> Ledger.get_transaction(id)
      _other -> nil
    end
  end

  defp editable(nil), do: :error

  defp editable(%{deleted_at: deleted_at, matched_transaction_id: matched})
       when not is_nil(deleted_at) or not is_nil(matched),
       do: :error

  defp editable(%{transfer_subtransaction: %{transaction_id: split_id}}),
    do: {:ok, Ledger.get_transaction!(split_id), true}

  defp editable(transaction), do: {:ok, transaction, false}

  defp load(%{assigns: %{scope: scope}} = socket, scope), do: socket

  defp load(socket, :all) do
    socket
    |> assign(scope: :all, account: nil, selected: MapSet.new())
    |> load_transactions()
  end

  defp load(socket, {:account, id} = scope) do
    account = Ledger.get_account!(id)

    socket
    |> assign(scope: scope, account: account, selected: MapSet.new())
    |> load_transactions()
  end

  defp load_transactions(socket),
    do: assign(socket, :transactions, Ledger.list_transactions(socket.assigns.account || :all))

  defp assign_rows(socket) do
    %{transactions: transactions, filter: filter, query: query} = socket.assigns
    account_rows = AccountGroups.rows(socket.assigns.account_groups)
    accounts = Map.new(account_rows, &{&1.account.id, &1.account})
    account = socket.assigns.account && Map.fetch!(accounts, socket.assigns.account.id)

    socket =
      assign(socket, account: account, page_title: (account && account.name) || "Alle Konten")

    rows = transactions |> Rows.filter(filter) |> Rows.search(query)
    balances = balances(account, account_rows)

    assign(socket,
      rows: rows,
      accounts: accounts,
      balances: balances,
      unapproved: Enum.reject(transactions, & &1.approved),
      running_balances: running_balances(socket.assigns, rows, balances),
      paths: view_paths(Map.put(socket.assigns, :accounts, accounts)),
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
  def handle_info({TransactionDialog, :done, message}, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> put_flash(:info, message)
     |> refresh()
     |> push_patch(to: socket.assigns.paths.list)}
  end

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
    case Enum.find(CategoryOptions.ids(socket.assigns.categories), &(Integer.to_string(&1) == id)) do
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
    do:
      socket
      |> put_flash(:error, "Nicht geändert: #{TransactionDialog.error_message(changeset)}")
      |> refresh()

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
      list: register_path(assigns, []),
      filters: Map.new(Rows.filters(), &{&1, register_path(assigns, filter: &1)}),
      running: register_path(assigns, running: !assigns.running),
      new: manual_entry?(assigns) && register_path(assigns, [], "/transactions/new"),
      edit: &register_path(assigns, [], "/transactions/#{&1}/edit")
    }
  end

  defp manual_entry?(%{account: nil, accounts: accounts}),
    do: Enum.any?(Map.values(accounts), &TransactionDialog.manual?/1)

  defp manual_entry?(%{account: account}), do: TransactionDialog.manual?(account)

  # The register's URL (or with `suffix` one below it) with the view, search and running balance, changed by
  # `changes`; defaults stay out.
  defp register_path(assigns, changes, suffix \\ "") do
    current = %{filter: assigns.filter, q: assigns.query, running: assigns.running}
    %{filter: filter, q: query, running: running} = Map.merge(current, Map.new(changes))

    params =
      [
        filter: filter != :all && filter,
        q: String.trim(query) != "" && query,
        running: running && "1"
      ]
      |> Enum.filter(fn {_key, value} -> value end)

    register = if assigns.account, do: ~p"/accounts/#{assigns.account}", else: ~p"/accounts/all"
    base = register <> suffix
    if params == [], do: base, else: base <> "?" <> Query.encode(params)
  end
end

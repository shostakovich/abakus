defmodule AbakusWeb.RegisterLive do
  @moduledoc """
  The register: one account's transactions (`/accounts/:id`) or every account's (`/accounts/all`), newest first under
  a heading per month. Its header has two rows: the name with its meta line and the pencil, beside them the balances
  and "Abgleichen" (in Alle Konten "Konto hinzufügen"); below, the toolbar. The view (`filter`) and the search (`q`)
  live in the URL; the selection does not, and whether the memo column shows is kept per device in the browser.

  It shows the view's newest 100 transactions and loads 100 more as its end comes near (the `LoadMore` hook), so an
  account opens as fast with thousands of transactions as with a few. A search goes through all of them, and "Alle
  auswählen" takes the whole view, loaded or not.

  Here transactions are approved (one, or all the view "Zu bestätigen" shows), categorised (the selected) and
  toggled between uncleared and cleared. A change to a reconciled transaction asks in the browser first and then sends
  `reconciled: "confirmed"`, which goes to the Ledger as `reconciled: :confirmed`. The shared-expenses account and
  closed accounts offer no manual entry and no reconcile; a closed account says so at the top with "Wieder öffnen".
  Alle Konten's Ansicht menu lists the closed accounts ("Geschlossene Konten (2) …"), which the sidebar leaves out.

  Above the transactions the scheduled transactions (`Abakus.Ledger.Scheduled`) show while there are any, collapsed;
  without any, Ansicht › "Geplante Buchungen" shows the empty list. A row enters its next occurrence now, where its
  account takes entries, or skips it, and opens `ScheduledDialog`, as "Geplante Buchung" adds one where manual
  entries go.
  Transactions linked to Kasse expenses are deleted only with their expense, those the Depot books not at all here.

  Match proposals are not in the register but shown among its rows, waiting like an unapproved transaction, with
  the transaction they match: "Zuordnen" merges them, "Trennen" keeps the import as a transaction of its own, and
  "Alle zuordnen" in the toolbar merges all. "Alle bestätigen" leaves them open, as that is a decision of its own.

  "Abgleichen" reconciles one account (`Reconcile`): its popover asks whether the balance is right, reconcile mode
  keeps the difference in a bar while transactions are cleared, until it is finished or cancelled.

  Ansicht › "Empfänger verwalten …" opens `PayeeDialog` on the payee of the one selected transaction, if any; once it
  renamed transactions, the register shows them anew. Its "(in N Buchungen)" searches Alle Konten for the payee, with
  the scheduled transactions open when some use it.

  The pencil beside the name opens the account form (`AbakusWeb.AccountDialog`); the account shown is the one in
  `account_groups`, so it is as fresh as the sidebar. The portfolios' cash is the Depot's
  (`Abakus.Depot.Portfolios.cash_account_portfolios/1`): Alle Konten leaves out its transactions, no account picker
  offers it but where a transaction uses it already, and its own register leads to its portfolio in the Depot.

  Transactions are edited as in YNAB, without a URL (`TransactionEditor`): a click selects a row (with ⌘ or Ctrl it
  joins the selection, with Shift the rows from the last one clicked; "Auswählen" in Ansicht makes every click join
  it, for touch screens), a click into a cell of a selected row opens the row for editing, "Buchung" adds an empty row
  on top; one row at a time. Phones open a sheet from a list row or the "+" button instead. The counterpart of a
  split's transfer opens its split. The selection bar categorises and deletes the selected transactions.
  """
  use AbakusWeb, :live_view

  alias Abakus.Depot.Portfolios
  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Scheduled, Transaction}
  alias Abakus.LocalTime
  alias AbakusWeb.{AccountGroups, CategoryOptions}
  alias AbakusWeb.Depot.Components, as: DepotComponents

  alias AbakusWeb.RegisterLive.{
    Balances,
    Components,
    PayeeDialog,
    Reconcile,
    Rows,
    ScheduledDialog,
    TransactionEditor
  }

  alias Plug.Conn.Query

  import TransactionEditor, only: [confirmed: 1]

  on_mount {AccountGroups, {:pass_on, [:synced, :move_account]}}

  @page 100
  @scheduled_gone "Die geplante Buchung gibt es nicht mehr."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={if @account, do: :accounts, else: :all_accounts}
      account_id={@account && @account.id}
      width={:full}
      account_groups={@account_groups}
      depot_sidebar={@depot_sidebar}
      expiring_consents={@expiring_consents}
      account_dialog={@account_dialog}
    >
      <:fab :if={@manual && !@editor}>
        <.fab id="new-transaction-fab" label="Buchung" phx-click="new" phx-value-layout="sheet" />
      </:fab>
      <div id="register">
        <.header class="app-reg-row app-reg-head pb-4 max-md:pb-3">
          <span id="register-title">{@page_title}</span>
          <:subtitle>
            <span class="inline-flex flex-wrap items-center gap-x-1">
              <Components.meta account={@account} />
              <.button
                :if={@account}
                id="edit-account"
                icon="pencil"
                icon_only
                label="Konto bearbeiten"
                variant={:ghost}
                size={:sm}
                phx-click="open_account_dialog"
                phx-value-id={@account.id}
              />
            </span>
          </:subtitle>
          <:actions>
            <div class="flex items-end gap-x-6 gap-y-2">
              <Components.balances
                account={@account}
                balances={@balances}
                reconciling={!!@reconciling}
              />
              <.button :if={!@account} id="add-account" icon="plus" phx-click="open_account_dialog">
                Konto hinzufügen
              </.button>
              <Reconcile.editor
                :if={@account && Account.reconcilable?(@account) && !@reconciling}
                state={@reconcile}
              />
            </div>
          </:actions>
        </.header>
        <Components.balance_line account={@account} balances={@balances} />
        <Components.closed_banner :if={@account && @account.closed} />
        <Components.toolbar
          account={@account}
          manual={@manual}
          unapproved={@unapproved}
          waiting={@waiting}
          proposals={@proposals}
          filter={@filter}
          query={@query}
          filter_paths={@filter_paths}
          unapproved_path={@unapproved_path}
          picking={@picking}
          all_selected={@count > 0 and MapSet.size(@selected) == @count}
          scheduled_toggle={if @scheduled == [] and @manual, do: @scheduled_shown}
          closed_count={if @account, do: 0, else: length(closed_rows(@account_groups))}
        />
        <Reconcile.bar :if={@reconciling} mode={@reconciling} />
        <Components.scheduled
          :if={@scheduled != [] or @scheduled_shown}
          scheduled={@scheduled}
          accounts={@accounts}
          all={is_nil(@account)}
          addable={@manual}
          open={@scheduled_open}
        />
        <Components.table
          rows={@rows}
          proposals={@shown_proposals}
          accounts={@accounts}
          columns={@columns}
          selected={@selected}
          editor={@editor && @editor.layout == :row && @editor}
          empty={empty_text(@accounts, @register_empty, @proposals)}
          empty_hint={empty_hint(@accounts)}
        />
        <Components.cards
          rows={@rows}
          proposals={@shown_proposals}
          accounts={@accounts}
          all={is_nil(@account)}
          empty={empty_text(@accounts, @register_empty, @proposals)}
          empty_hint={empty_hint(@accounts)}
        />
        <Components.load_more :if={@count > length(@rows)} />
        <Components.legend />
        <Components.bulk
          selected={if @editor, do: [], else: @selection}
          categories={@categories || []}
        />
      </div>
      <.live_component
        :if={@editor && @editor.layout == :sheet}
        module={TransactionEditor}
        {@editor.assigns}
      />
      <.live_component :if={@scheduled_dialog} module={ScheduledDialog} {@scheduled_dialog} />
      <.live_component :if={@payee_dialog} module={PayeeDialog} {@payee_dialog} />
      <Components.closed_accounts :if={@closed_accounts} rows={closed_rows(@account_groups)} />
    </Layouts.app>
    """
  end

  defp empty_text(accounts, _register_empty, _proposals) when accounts == %{},
    do: "Noch keine Konten"

  defp empty_text(_accounts, true, []), do: "Noch keine Buchungen"
  defp empty_text(_accounts, _register_empty, _proposals), do: "Keine Buchungen in dieser Ansicht"

  defp empty_hint(accounts) when accounts == %{},
    do: "Lege mit „Konto hinzufügen“ ein Konto an, um Buchungen zu erfassen oder zu importieren."

  defp empty_hint(_accounts), do: nil

  defp closed_rows(groups) do
    case Enum.find(groups, &(&1.key == :closed)) do
      nil -> []
      group -> group.rows
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    depot_cash = Portfolios.cash_account_portfolios(scope)

    {:ok,
     assign(socket,
       depot_cash: depot_cash,
       cash_accounts: Enum.filter(Ledger.list_accounts(scope), &Map.has_key?(depot_cash, &1.id)),
       today: LocalTime.today(),
       scope: nil,
       editor: nil,
       selected: MapSet.new(),
       selection: [],
       anchor: nil,
       picking: false,
       categories: nil,
       reconcile: nil,
       reconciling: nil,
       scheduled_shown: false,
       scheduled_open: false,
       scheduled_dialog: nil,
       payee_dialog: nil,
       closed_accounts: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case depot_portfolio_id(socket.assigns.depot_cash, params) do
      nil ->
        view = %{scope: scope(params), filter: filter(params["filter"]), query: params["q"] || ""}

        {:noreply,
         socket
         |> show(view)
         |> load_transactions()
         |> load_scheduled()
         |> assign_rows()}

      portfolio_id ->
        {:noreply,
         push_navigate(socket, to: DepotComponents.depots_path(:holdings, portfolio_id))}
    end
  end

  defp depot_portfolio_id(depot_cash, %{"id" => id}),
    do:
      Enum.find_value(depot_cash, fn {account_id, portfolio_id} ->
        to_string(account_id) == id && portfolio_id
      end)

  defp depot_portfolio_id(_depot_cash, _params), do: nil

  # Another view or search starts again at its newest transactions.
  defp show(socket, view) do
    if Map.take(socket.assigns, [:scope, :filter, :query]) == view,
      do: socket,
      else:
        socket
        |> assign(filter: view.filter, query: view.query, limit: @page, selection: [])
        |> load(view.scope)
  end

  defp scope(%{"id" => id}), do: {:account, id}
  defp scope(_params), do: :all

  defp editable(_current_scope, nil), do: :error

  defp editable(_current_scope, %{deleted_at: deleted_at, matched_transaction_id: matched})
       when not is_nil(deleted_at) or not is_nil(matched),
       do: :error

  defp editable(current_scope, %{transfer_subtransaction: %{transaction_id: split_id}}),
    do: {:ok, Ledger.get_transaction!(current_scope, split_id), true}

  defp editable(_current_scope, transaction), do: {:ok, transaction, false}

  defp load(%{assigns: %{scope: scope}} = socket, scope), do: socket

  defp load(socket, :all) do
    socket
    |> assign(scope: :all, account: nil, selected: MapSet.new(), editor: nil)
    |> assign(reconcile: nil, reconciling: nil, scheduled_shown: false, scheduled_dialog: nil)
  end

  defp load(socket, {:account, id} = scope) do
    account = Ledger.get_account!(socket.assigns.current_scope, id)

    socket
    |> assign(scope: scope, account: account, selected: MapSet.new(), editor: nil)
    |> assign(reconcile: nil, reconciling: nil, scheduled_shown: false, scheduled_dialog: nil)
  end

  # A search compares in memory, so it goes through all of the view's transactions.
  defp load_transactions(socket) do
    %{current_scope: current_scope, filter: filter, limit: limit} = assigns = socket.assigns
    {register, shown} = register(assigns)

    {rows, count} =
      if Rows.searching?(assigns.query) do
        found = view(assigns, [])
        {Enum.take(found, limit), length(found)}
      else
        {view(assigns, limit: limit),
         Ledger.count_transactions(current_scope, register, [filter: filter] ++ shown)}
      end

    assign(socket,
      rows: rows,
      count: count,
      register_empty:
        count == 0 and Ledger.count_transactions(current_scope, register, shown) == 0,
      unapproved:
        Ledger.list_transactions(current_scope, register, [filter: :unapproved] ++ shown),
      proposals: Ledger.list_match_proposals(current_scope, register, shown)
    )
  end

  defp load_scheduled(%{assigns: assigns} = socket) do
    {register, shown} = register(assigns)

    socket
    |> assign(:scheduled, Scheduled.list(assigns.current_scope, register, shown))
    |> keep_scheduled_open()
  end

  # The list follows `open`, so it turns false only while the list is not there, closing nothing.
  defp keep_scheduled_open(%{assigns: %{scheduled: [], scheduled_shown: shown}} = socket),
    do: assign(socket, :scheduled_open, shown)

  defp keep_scheduled_open(socket), do: socket

  # The list opens when `open` turns true, so it goes false first: it opens also after the user closed it.
  defp reopen_scheduled(socket) do
    send(self(), :open_scheduled)
    assign(socket, :scheduled_open, false)
  end

  defp view(assigns, opts) do
    {register, shown} = register(assigns)

    assigns.current_scope
    |> Ledger.list_transactions(register, [filter: assigns.filter] ++ shown ++ opts)
    |> Rows.search(assigns.query)
  end

  defp register(%{account: nil, depot_cash: depot_cash}),
    do: {:all, without_accounts: Map.keys(depot_cash)}

  defp register(%{account: account}), do: {account, []}

  defp assign_rows(socket) do
    %{rows: rows, filter: filter, query: query} = socket.assigns
    account_rows = AccountGroups.rows(socket.assigns.account_groups)

    accounts =
      Map.new(Enum.map(account_rows, & &1.account) ++ socket.assigns.cash_accounts, &{&1.id, &1})

    account = socket.assigns.account && Map.fetch!(accounts, socket.assigns.account.id)

    socket =
      assign(socket, account: account, page_title: (account && account.name) || "Alle Konten")

    shown_proposals = socket.assigns.proposals |> Rows.filter(filter) |> Rows.search(query)

    waiting =
      if filter == :unapproved, do: Rows.search(socket.assigns.unapproved, query), else: []

    balances = balances(account, account_rows)
    columns = Components.columns(account)

    socket
    |> assign(
      shown_proposals: shown_proposals,
      waiting: waiting,
      accounts: accounts,
      manual: manual_entry?(account, account_rows),
      columns: columns,
      editor: follow_rows(socket.assigns.editor, rows, accounts, columns),
      balances: balances,
      filter_paths: Map.new(Rows.filters(), &{&1, register_path(socket.assigns, filter: &1)}),
      unapproved_path: register_path(socket.assigns, filter: :unapproved, q: "")
    )
    |> select(socket.assigns.selected)
  end

  defp select(socket, %MapSet{} = ids) do
    %{rows: rows, selection: selection} = socket.assigns
    known = (rows ++ selection) |> Enum.filter(&(&1.id in ids)) |> Enum.uniq_by(& &1.id)

    if length(known) == MapSet.size(ids),
      do: select(socket, known),
      else: select(socket, view(socket.assigns, ids: MapSet.to_list(ids)))
  end

  defp select(socket, transactions) when is_list(transactions) do
    socket
    |> assign(selected: MapSet.new(transactions, & &1.id), selection: transactions)
    |> assign_categories()
  end

  # The selection bar's category picker reads the whole budget, so it is built only once something is selected.
  defp assign_categories(%{assigns: assigns} = socket) do
    cond do
      MapSet.size(assigns.selected) == 0 ->
        assign(socket, :categories, nil)

      assigns.categories ->
        socket

      true ->
        assign(socket, :categories, CategoryOptions.build(assigns.current_scope, assigns.today))
    end
  end

  defp follow_rows(nil, _rows, _accounts, _columns), do: nil

  defp follow_rows(editor, rows, accounts, columns) do
    if shown?(editor, rows),
      do: update_in(editor.assigns, &Map.merge(&1, %{accounts: accounts, columns: columns})),
      else: nil
  end

  defp shown?(%{layout: :row, row_id: id}, rows) when id != :new,
    do: Enum.any?(rows, &(&1.id == id))

  defp shown?(_editor, _rows), do: true

  defp balances(nil, account_rows), do: Balances.all(account_rows)

  defp balances(account, account_rows),
    do: account_rows |> Enum.find(&(&1.account.id == account.id)) |> Balances.account()

  @impl true
  def handle_info({TransactionEditor, :done, message}, socket) do
    {:noreply,
     socket
     |> assign(:editor, nil)
     |> clear_flash()
     |> put_flash(:info, message)
     |> refresh()}
  end

  def handle_info({ScheduledDialog, :done, message}, socket) do
    {:noreply,
     socket
     |> assign(:scheduled_dialog, nil)
     |> clear_flash()
     |> put_flash(:info, message)
     |> refresh()}
  end

  def handle_info({PayeeDialog, :changed}, socket), do: {:noreply, refresh(socket)}

  def handle_info({PayeeDialog, :flash, kind, message}, socket),
    do: {:noreply, socket |> clear_flash() |> put_flash(kind, message)}

  def handle_info({PayeeDialog, :show_transactions, name, scheduled}, socket) do
    socket = if scheduled, do: reopen_scheduled(socket), else: socket

    {:noreply,
     socket
     |> assign(:payee_dialog, nil)
     |> push_patch(to: ~p"/budget/accounts/all?#{[q: name]}")}
  end

  def handle_info(:open_scheduled, socket), do: {:noreply, assign(socket, :scheduled_open, true)}

  def handle_info({:synced, _device}, socket) do
    if socket.assigns.payee_dialog,
      do: send_update(PayeeDialog, id: socket.assigns.payee_dialog.id, synced: true)

    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("move_account", _params, socket), do: {:noreply, assign_rows(socket)}

  def handle_event("search", %{"q" => query}, socket),
    do: {:noreply, push_patch(socket, to: register_path(socket.assigns, q: query))}

  def handle_event("toggle_cleared", %{"id" => id} = params, socket) do
    change(socket, id, fn transaction ->
      Ledger.update_transaction(
        socket.assigns.current_scope,
        transaction,
        %{cleared: toggled(transaction.cleared)},
        confirmed(params)
      )
    end)
  end

  def handle_event("approve", %{"id" => id} = params, socket) do
    change(
      socket,
      id,
      &Ledger.update_transaction(
        socket.assigns.current_scope,
        &1,
        %{approved: true},
        confirmed(params)
      )
    )
  end

  def handle_event("approve_shown", params, %{assigns: %{waiting: [_ | _] = waiting}} = socket) do
    socket
    |> saved(
      Ledger.update_transactions(
        socket.assigns.current_scope,
        waiting,
        %{approved: true},
        confirmed(params)
      ),
      "#{length(waiting)} bestätigt.#{open_proposals_text(socket.assigns.shown_proposals)}"
    )
    |> noreply()
  end

  def handle_event("approve_shown", _params, socket), do: {:noreply, socket}

  def handle_event("accept_match", %{"id" => id} = params, socket) do
    decide(
      socket,
      id,
      &Ledger.accept_match(socket.assigns.current_scope, &1, confirmed(params)),
      "Zugeordnet."
    )
  end

  def handle_event("reject_match", %{"id" => id}, socket) do
    decide(
      socket,
      id,
      &Ledger.reject_match(socket.assigns.current_scope, &1),
      "Getrennt und als eigene Buchung bestätigt."
    )
  end

  def handle_event("accept_all_matches", params, socket) do
    proposals = socket.assigns.proposals

    socket
    |> saved(
      Ledger.accept_matches(socket.assigns.current_scope, proposals, confirmed(params)),
      "#{length(proposals)} zugeordnet."
    )
    |> noreply()
  end

  def handle_event("categorise_selected", %{"category_id" => id} = params, socket) do
    case Enum.find(CategoryOptions.ids(socket.assigns.categories || []), &(&1 == id)) do
      nil -> {:noreply, socket}
      category_id -> categorise(socket, category_id, params)
    end
  end

  # While a row is edited the other rows wait, as only one is edited at a time.
  def handle_event("row_click", _params, %{assigns: %{editor: editor}} = socket)
      when not is_nil(editor),
      do: {:noreply, socket}

  def handle_event("row_click", %{"id" => id} = params, socket) do
    case find(socket, id) do
      nil ->
        {:noreply, socket}

      transaction ->
        {:noreply, click_row(socket, transaction, params)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket),
    do: {:noreply, open_editor(socket, id, :sheet, nil)}

  def handle_event("new", %{"layout" => layout}, socket) do
    if socket.assigns.manual do
      layout = if layout == "sheet", do: :sheet, else: :row
      {:noreply, assign(socket, :editor, editor(socket, :new, nil, false, layout, "date"))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, :editor, nil)}

  def handle_event("toggle_scheduled", _params, socket),
    do: {:noreply, socket |> update(:scheduled_shown, &(!&1)) |> keep_scheduled_open()}

  def handle_event("new_scheduled", _params, socket) do
    if socket.assigns.manual,
      do: {:noreply, open_scheduled(socket, nil)},
      else: {:noreply, socket}
  end

  def handle_event("edit_scheduled", %{"id" => id}, socket) do
    case Scheduled.get(socket.assigns.current_scope, id) do
      nil -> {:noreply, socket |> put_flash(:error, @scheduled_gone) |> refresh()}
      scheduled -> {:noreply, open_scheduled(socket, scheduled)}
    end
  end

  def handle_event("close_scheduled_dialog", _params, socket),
    do: {:noreply, assign(socket, :scheduled_dialog, nil)}

  def handle_event("enter_scheduled", %{"id" => id}, socket) do
    %{scheduled: scheduled, accounts: accounts} = socket.assigns
    enterable = Enum.filter(scheduled, &Account.takes_entries?(accounts[&1.account_id]))
    scheduled_action(socket, enterable, id, &Scheduled.enter_now/2, "Gebucht.")
  end

  def handle_event("skip_scheduled", %{"id" => id}, socket),
    do: scheduled_action(socket, socket.assigns.scheduled, id, &Scheduled.skip/2, "Übersprungen.")

  def handle_event(
        "reopen_account",
        _params,
        %{assigns: %{account: %Account{} = account}} = socket
      ) do
    {:ok, _account} =
      Ledger.update_account(socket.assigns.current_scope, account, %{closed: false})

    {:noreply, socket |> clear_flash() |> put_flash(:info, "Konto wieder geöffnet.") |> refresh()}
  end

  def handle_event("open_payee_dialog", _params, %{assigns: assigns} = socket) do
    payee_id =
      case assigns.selection do
        [transaction] -> transaction.payee_id
        _selection -> nil
      end

    {:noreply,
     assign(socket,
       editor: nil,
       payee_dialog: %{
         id: "payee-dialog",
         current_scope: assigns.current_scope,
         today: assigns.today,
         payee_id: payee_id
       }
     )}
  end

  def handle_event("close_payee_dialog", _params, socket),
    do: {:noreply, assign(socket, :payee_dialog, nil)}

  def handle_event("show_closed_accounts", _params, socket),
    do: {:noreply, assign(socket, :closed_accounts, true)}

  def handle_event("close_closed_accounts", _params, socket),
    do: {:noreply, assign(socket, :closed_accounts, false)}

  def handle_event("delete_selected", params, socket) do
    case socket.assigns.selection do
      [] ->
        {:noreply, socket}

      transactions ->
        transactions =
          transactions
          |> Enum.map(&deletable(socket.assigns.current_scope, &1))
          |> Enum.uniq_by(& &1.id)

        delete(socket, transactions, params)
    end
  end

  def handle_event("toggle_picking", _params, socket),
    do: {:noreply, update(socket, :picking, &(!&1))}

  def handle_event("select_all", _params, %{assigns: assigns} = socket) do
    if MapSet.size(assigns.selected) == assigns.count,
      do: {:noreply, select(socket, [])},
      else: {:noreply, select(socket, view(assigns, []))}
  end

  def handle_event("clear_selection", _params, socket),
    do: {:noreply, socket |> assign(:picking, false) |> select([])}

  def handle_event("load_more", _params, %{assigns: assigns} = socket) do
    if assigns.count > length(assigns.rows),
      do:
        {:noreply,
         socket |> update(:limit, &(&1 + @page)) |> load_transactions() |> assign_rows()},
      else: {:noreply, socket}
  end

  def handle_event(
        "reconcile_open",
        _params,
        %{assigns: %{account: %Account{} = account}} = socket
      ) do
    if Account.reconcilable?(account),
      do: {:noreply, assign(socket, :reconcile, ask(socket, account))},
      else: {:noreply, socket}
  end

  def handle_event("reconcile_close", _params, socket),
    do: {:noreply, assign(socket, :reconcile, nil)}

  def handle_event("reconcile_no", _params, %{assigns: %{reconcile: %{} = state}} = socket),
    do: {:noreply, assign(socket, :reconcile, %{state | step: :enter, error: nil})}

  def handle_event(
        "reconcile_yes",
        _params,
        %{assigns: %{reconcile: %{bank: bank}}} = socket
      ),
      do: {:noreply, reconcile(socket, bank, adjust: 0)}

  def handle_event(
        "reconcile_search",
        _params,
        %{assigns: %{reconcile: %{bank: bank}}} = socket
      ),
      do: {:noreply, start_reconciling(socket, bank)}

  def handle_event(
        "reconcile_start",
        %{"balance" => text},
        %{assigns: %{reconcile: %{} = state}} = socket
      ) do
    case Reconcile.entered(text, socket.assigns.today) do
      {:ok, bank} -> {:noreply, start_reconciling(socket, bank)}
      {:error, message} -> {:noreply, assign(socket, :reconcile, %{state | error: message})}
    end
  end

  def handle_event("reconcile_cancel", _params, socket),
    do: {:noreply, assign(socket, :reconciling, nil)}

  def handle_event(
        "reconcile_finish",
        _params,
        %{assigns: %{reconciling: %{bank: bank} = mode}} = socket
      ),
      do: {:noreply, reconcile(socket, bank, adjust: Reconcile.difference(mode))}

  # Late clicks after the popover closed or the mode ended.
  def handle_event("reconcile_" <> _event, _params, socket), do: {:noreply, socket}

  defp open_scheduled(socket, scheduled) do
    %{assigns: assigns} = socket

    assign(socket,
      editor: nil,
      scheduled_dialog: %{
        id: "scheduled-dialog",
        current_scope: assigns.current_scope,
        scheduled: scheduled,
        account: assigns.account,
        accounts: assigns.accounts,
        depot_cash: assigns.depot_cash,
        today: assigns.today
      }
    )
  end

  defp scheduled_action(socket, offered, id, action, message) do
    case Enum.find(offered, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      scheduled ->
        case action.(socket.assigns.current_scope, scheduled) do
          {:ok, _scheduled} ->
            {:noreply, socket |> clear_flash() |> put_flash(:info, message) |> refresh()}

          {:error, :not_found} ->
            {:noreply, socket |> put_flash(:error, @scheduled_gone) |> refresh()}

          {:error, changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, "Nicht gebucht: #{TransactionEditor.error_message(changeset)}")
             |> refresh()}
        end
    end
  end

  defp ask(socket, account) do
    %{current_scope: current_scope, today: today} = socket.assigns

    bank =
      case Ledger.latest_bank_balance(current_scope, account) do
        nil -> Reconcile.bank(Ledger.cleared_balance(current_scope, account, today), today)
        stored -> Reconcile.bank(stored)
      end

    current_scope |> reconcile_mode(account, bank) |> Map.merge(%{step: :ask, error: nil})
  end

  defp start_reconciling(socket, bank) do
    %{current_scope: current_scope, account: account} = socket.assigns
    assign(socket, reconcile: nil, reconciling: reconcile_mode(current_scope, account, bank))
  end

  defp reconcile(socket, bank, opts) do
    socket = assign(socket, reconcile: nil)

    case Ledger.reconcile(socket.assigns.current_scope, socket.assigns.account, bank, opts) do
      {:ok, result} ->
        socket |> assign(:reconciling, nil) |> saved({:ok, result}, Reconcile.done_text(result))

      {:error, {:difference, difference}} ->
        socket |> put_flash(:error, Reconcile.refused_text(difference)) |> refresh()

      {:error, changeset} ->
        saved(socket, {:error, changeset})
    end
  end

  defp delete(socket, transactions, params) do
    with nil <- refused_delete(socket.assigns.current_scope, transactions),
         {:ok, deleted} <-
           Ledger.delete_transactions(
             socket.assigns.current_scope,
             transactions,
             confirmed(params)
           ) do
      socket
      |> assign(:selected, MapSet.new())
      |> saved({:ok, deleted}, deleted_text(length(deleted)))
      |> noreply()
    else
      reason when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, "Nicht gelöscht: #{reason}")}

      {:error, changeset} ->
        socket
        |> put_flash(:error, "Nicht gelöscht: #{TransactionEditor.error_message(changeset)}")
        |> refresh()
        |> noreply()
    end
  end

  defp refused_delete(scope, transactions) do
    cond do
      Enum.any?(transactions, &match?({:kasse_expense, _id}, Ledger.led_by(scope, &1))) ->
        TransactionEditor.linked_delete()

      Enum.any?(transactions, &match?({:depot_transaction, _id}, Ledger.led_by(scope, &1))) ->
        TransactionEditor.depot_delete()

      true ->
        nil
    end
  end

  defp deleted_text(1), do: "Buchung gelöscht."
  defp deleted_text(count), do: "#{count} Buchungen gelöscht."

  # The counterpart of a split's transfer goes with its split, as it is edited there.
  defp deletable(current_scope, %Transaction{transfer_subtransaction_id: id} = transaction)
       when not is_nil(id) do
    %{transfer_subtransaction: %{transaction_id: split_id}} =
      Ledger.get_transaction!(current_scope, transaction.id)

    %Transaction{id: split_id}
  end

  defp deletable(_current_scope, transaction), do: transaction

  defp open_editor(socket, id, layout, field) do
    current_scope = socket.assigns.current_scope

    row = Ledger.get_transaction(current_scope, id)

    case editable(current_scope, row) do
      {:ok, transaction, split_of} ->
        row_id = row.id

        socket
        |> then(&if(layout == :row, do: select(&1, MapSet.new([row_id])), else: &1))
        |> assign(
          :editor,
          editor(socket, row_id, transaction, split_of, layout, field || "payee")
        )

      :error ->
        socket
        |> assign(:editor, nil)
        |> put_flash(:error, "Buchung nicht gefunden.")
        |> refresh()
    end
  end

  defp editor(socket, row_id, transaction, split_of, layout, focus) do
    %{assigns: assigns} = socket

    %{
      row_id: row_id,
      layout: layout,
      assigns: %{
        id: "tx-editor",
        current_scope: assigns.current_scope,
        transaction: transaction,
        split_of: split_of,
        layout: layout,
        focus: focus_id(focus),
        account: assigns.account,
        accounts: assigns.accounts,
        depot_cash: assigns.depot_cash,
        columns: assigns.columns,
        today: assigns.today
      }
    }
  end

  defp focus_id("account"), do: "tx-account"

  defp focus_id(field) when field in ~w(date payee category memo amount),
    do: "tx-#{field}"

  defp focus_id(_field), do: "tx-payee"

  # A reconciled transaction is unlocked to cleared, so the cleared balance stays as it is.
  defp toggled(:uncleared), do: :cleared
  defp toggled(:cleared), do: :uncleared
  defp toggled(:reconciled), do: :cleared

  defp toggle(set, id), do: if(id in set, do: MapSet.delete(set, id), else: MapSet.put(set, id))

  defp click_row(socket, transaction, params) do
    %{selected: selected, picking: picking} = socket.assigns

    cond do
      params["range"] && socket.assigns.anchor ->
        select(
          socket,
          MapSet.new(span(socket.assigns.rows, socket.assigns.anchor, transaction.id))
        )

      params["range"] ->
        socket |> assign(:anchor, transaction.id) |> select([transaction])

      params["toggle"] || picking ->
        socket |> assign(:anchor, transaction.id) |> select(toggle(selected, transaction.id))

      transaction.id in selected ->
        open_editor(socket, transaction.id, :row, params["field"])

      true ->
        socket |> assign(:anchor, transaction.id) |> select([transaction])
    end
  end

  # The ids from one row to another in the shown order, both included.
  defp span(rows, from, to) do
    ids = Enum.map(rows, & &1.id)

    case {Enum.find_index(ids, &(&1 == from)), Enum.find_index(ids, &(&1 == to))} do
      {nil, _to} -> [to]
      {first, last} -> Enum.slice(ids, min(first, last)..max(first, last)//1)
    end
  end

  defp change(socket, id, fun) do
    case find(socket, id) do
      nil -> {:noreply, socket}
      transaction -> socket |> saved(fun.(transaction)) |> noreply()
    end
  end

  defp open_proposals_text([]), do: ""
  defp open_proposals_text([_]), do: " 1 Zuordnungsvorschlag bleibt offen: Zuordnen oder Trennen."

  defp open_proposals_text(proposals),
    do: " #{length(proposals)} Zuordnungsvorschläge bleiben offen: Zuordnen oder Trennen."

  defp decide(socket, id, fun, message) do
    case Enum.find(socket.assigns.proposals, &(&1.id == id)) do
      nil -> {:noreply, socket}
      proposal -> socket |> saved(fun.(proposal), message) |> noreply()
    end
  end

  defp categorise(socket, category_id, params) do
    case Enum.filter(socket.assigns.selection, &Rows.categorisable?(&1, socket.assigns.accounts)) do
      [] ->
        {:noreply,
         put_flash(socket, :error, "Keine der ausgewählten Buchungen nimmt eine Kategorie.")}

      transactions ->
        result =
          Ledger.update_transactions(
            socket.assigns.current_scope,
            transactions,
            %{category_id: category_id},
            confirmed(params)
          )

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
      |> put_flash(:error, "Nicht geändert: #{TransactionEditor.error_message(changeset)}")
      |> refresh()

  defp refresh(socket) do
    socket
    |> assign(:account_groups, AccountGroups.load(socket.assigns.current_scope))
    |> assign(categories: nil, selection: [])
    |> load_transactions()
    |> load_scheduled()
    |> assign_rows()
    |> update(:reconciling, &follow_cleared(&1, socket.assigns))
  end

  defp follow_cleared(nil, _assigns), do: nil

  defp follow_cleared(%{bank: bank}, assigns),
    do: reconcile_mode(assigns.current_scope, assigns.account, bank)

  defp reconcile_mode(current_scope, account, bank),
    do: %{bank: bank, cleared: Ledger.cleared_balance(current_scope, account, bank.through)}

  defp noreply(socket), do: {:noreply, socket}

  defp find(socket, id),
    do: Enum.find(socket.assigns.rows, &(&1.id == id))

  defp filter(param), do: Enum.find(Rows.filters(), :all, &(Atom.to_string(&1) == param))

  # With no account taking manual entries there is nothing to book in.
  defp manual_entry?(nil, account_rows),
    do: Enum.any?(account_rows, &Account.takes_entries?(&1.account))

  defp manual_entry?(account, _accounts), do: Account.takes_entries?(account)

  defp register_path(assigns, changes) do
    current = %{filter: assigns.filter, q: assigns.query}
    %{filter: filter, q: query} = Map.merge(current, Map.new(changes))

    params =
      [
        filter: filter != :all && filter,
        q: String.trim(query) != "" && query
      ]
      |> Enum.filter(fn {_key, value} -> value end)

    base =
      if assigns.account,
        do: ~p"/budget/accounts/#{assigns.account}",
        else: ~p"/budget/accounts/all"

    if params == [], do: base, else: base <> "?" <> Query.encode(params)
  end
end

defmodule AbakusWeb.RegisterLive do
  @moduledoc """
  The register: one account's transactions (`/accounts/:id`) or every account's (`/accounts/all`), newest first. Its
  header has three rows, as in YNAB: the name with its meta line and the actions (pencil, "Abgleichen"; in Alle Konten
  "Konto hinzufügen"), the balances, and the toolbar. The view (`filter`), the search (`q`) and the running balance
  (`running`, one account in the full list only) live in the URL; the selection does not, and whether the memo column
  shows is kept per device in the browser.

  It shows the view's newest 100 transactions and loads 100 more as its end comes near (the `LoadMore` hook), so an
  account opens as fast with thousands of transactions as with a few. A search goes through all of them, and "Alle
  auswählen" takes the whole view, loaded or not.

  Here transactions are approved (one, the selected or all), categorised (the selected) and toggled
  between uncleared and cleared. A change to a reconciled transaction asks in the browser first and then sends
  `reconciled: "confirmed"`, which goes to the Ledger as `reconciled: :confirmed`. The shared-expenses account offers
  no manual entry and no reconcile.
  Transactions linked to Kasse expenses are deleted only with their expense, those the Depot books not at all here.

  Match proposals are not in the register but shown among its rows, waiting like an unapproved transaction, with
  the transaction they match: "Zuordnen" merges them, "Trennen" keeps the import as a transaction of its own, and
  "Alle zuordnen" in the toolbar merges all. "Alle bestätigen" leaves them open, as that is a decision of its own.

  "Abgleichen" reconciles one account (`Reconcile`): its popover asks whether the balance is right, reconcile mode
  keeps the difference in a bar while transactions are cleared, until it is finished or cancelled.

  The pencil beside the name opens the account form (`AbakusWeb.AccountDialog`); the account shown is the one in
  `account_groups`, so it is as fresh as the sidebar.

  Transactions are edited as in YNAB, without a URL (`TransactionEditor`): a click selects a row, a click into a
  cell of a selected row opens the row for editing, "Buchung" adds an empty row on top; one row at a time. Phones
  open a sheet from a list row or the "+" button instead. The counterpart of a split's transfer opens its
  split. The selection bar approves, categorises and deletes the selected transactions.
  """
  use AbakusWeb, :live_view

  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Transaction}
  alias Abakus.LocalTime
  alias AbakusWeb.{AccountGroups, CategoryOptions}
  alias AbakusWeb.RegisterLive.{Balances, Components, Reconcile, Rows, TransactionEditor}
  alias Plug.Conn.Query

  import TransactionEditor, only: [confirmed: 1]

  @page 100

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
      account_dialog={@account_dialog}
    >
      <:fab :if={@manual && !@editor}>
        <.fab id="new-transaction-fab" label="Buchung" phx-click="new" phx-value-layout="sheet" />
      </:fab>
      <div id="register">
        <.header class="app-reg-row pb-4 max-md:pb-3">
          <span id="register-title">{@page_title}</span>
          <:subtitle><Components.meta account={@account} /></:subtitle>
          <:actions :if={!@account}>
            <.button id="add-account" icon="plus" phx-click="open_account_dialog">
              Konto hinzufügen
            </.button>
          </:actions>
          <:actions :if={@account}>
            <.button
              id="edit-account"
              icon="pencil"
              icon_only
              label="Konto bearbeiten"
              variant={:ghost}
              phx-click="open_account_dialog"
              phx-value-id={@account.id}
            />
            <Reconcile.editor
              :if={Account.reconcilable?(@account) && !@reconciling}
              state={@reconcile}
            />
          </:actions>
        </.header>
        <Components.balances account={@account} balances={@balances} reconciling={!!@reconciling} />
        <Components.toolbar
          account={@account}
          manual={@manual}
          unapproved={@unapproved}
          proposals={@proposals}
          filter={@filter}
          query={@query}
          running={@running}
          running_shown={@running_balances != nil}
          paths={@paths}
        />
        <Reconcile.bar :if={@reconciling} mode={@reconciling} />
        <Components.table
          rows={@rows}
          count={@count}
          proposals={@shown_proposals}
          accounts={@accounts}
          columns={@columns}
          selected={@selected}
          running={@running_balances}
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

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       today: LocalTime.today(),
       scope: nil,
       editor: nil,
       selected: MapSet.new(),
       selection: [],
       categories: nil,
       reconcile: nil,
       reconciling: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view = %{scope: scope(params), filter: filter(params["filter"]), query: params["q"] || ""}

    {:noreply,
     socket
     |> assign(:running, params["running"] == "1")
     |> show(view)
     |> load_transactions()
     |> assign_rows()}
  end

  # Another view or search starts again at its newest transactions; the running balance changes neither.
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

  defp fetch_transaction(current_scope, id) when is_integer(id),
    do: Ledger.get_transaction(current_scope, id)

  defp fetch_transaction(current_scope, id) do
    case Integer.parse(id) do
      {id, ""} -> Ledger.get_transaction(current_scope, id)
      _other -> nil
    end
  end

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
    |> assign(reconcile: nil, reconciling: nil)
  end

  defp load(socket, {:account, id} = scope) do
    account = Ledger.get_account!(socket.assigns.current_scope, id)

    socket
    |> assign(scope: scope, account: account, selected: MapSet.new(), editor: nil)
    |> assign(reconcile: nil, reconciling: nil)
  end

  # A search compares in memory, so it goes through all of the view's transactions.
  defp load_transactions(socket) do
    %{current_scope: current_scope, filter: filter, limit: limit} = assigns = socket.assigns
    register = register(assigns)

    {rows, count} =
      if Rows.searching?(assigns.query) do
        found = view(assigns, [])
        {Enum.take(found, limit), length(found)}
      else
        {view(assigns, limit: limit),
         Ledger.count_transactions(current_scope, register, filter: filter)}
      end

    assign(socket,
      rows: rows,
      count: count,
      register_empty: count == 0 and Ledger.count_transactions(current_scope, register) == 0,
      unapproved: Ledger.list_transactions(current_scope, register, filter: :unapproved),
      proposals: Ledger.list_match_proposals(current_scope, register)
    )
  end

  defp view(assigns, opts) do
    assigns.current_scope
    |> Ledger.list_transactions(register(assigns), [filter: assigns.filter] ++ opts)
    |> Rows.search(assigns.query)
  end

  defp register(assigns), do: assigns.account || :all

  defp assign_rows(socket) do
    %{rows: rows, filter: filter, query: query} = socket.assigns
    account_rows = AccountGroups.rows(socket.assigns.account_groups)
    accounts = Map.new(account_rows, &{&1.account.id, &1.account})
    account = socket.assigns.account && Map.fetch!(accounts, socket.assigns.account.id)

    socket =
      assign(socket, account: account, page_title: (account && account.name) || "Alle Konten")

    shown_proposals = socket.assigns.proposals |> Rows.filter(filter) |> Rows.search(query)
    balances = balances(account, account_rows)
    running = running_balances(socket.assigns, rows, balances)
    columns = Components.columns(account, running != nil)

    socket
    |> assign(
      shown_proposals: shown_proposals,
      accounts: accounts,
      manual: manual_entry?(account, accounts),
      columns: columns,
      editor: follow_rows(socket.assigns.editor, rows, accounts, columns),
      balances: balances,
      running_balances: running,
      paths: view_paths(Map.put(socket.assigns, :accounts, accounts))
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
  def handle_info({TransactionEditor, :done, message}, socket) do
    {:noreply,
     socket
     |> assign(:editor, nil)
     |> clear_flash()
     |> put_flash(:info, message)
     |> refresh()}
  end

  @impl true
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

  def handle_event("approve_all", params, socket) do
    approve(socket, socket.assigns.unapproved, params, & &1, open_proposals_text(socket))
  end

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

  def handle_event("approve_selected", params, socket) do
    case Enum.reject(socket.assigns.selection, & &1.approved) do
      [] ->
        {:noreply,
         put_flash(socket, :info, "Keine der ausgewählten Buchungen wartet auf Bestätigung.")}

      waiting ->
        approve(socket, waiting, params, &assign(&1, :selected, MapSet.new()))
    end
  end

  def handle_event("categorise_selected", %{"category_id" => id} = params, socket) do
    case Enum.find(
           CategoryOptions.ids(socket.assigns.categories || []),
           &(Integer.to_string(&1) == id)
         ) do
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

      %{id: id} = transaction ->
        if id in socket.assigns.selected,
          do: {:noreply, open_editor(socket, transaction.id, :row, params["field"])},
          else: {:noreply, select(socket, [transaction])}
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

  def handle_event("select", %{"id" => id}, socket) do
    case find(socket, id) do
      nil -> {:noreply, socket}
      transaction -> {:noreply, select(socket, toggle(socket.assigns.selected, transaction.id))}
    end
  end

  def handle_event("select_all", _params, %{assigns: assigns} = socket) do
    if MapSet.size(assigns.selected) == assigns.count,
      do: {:noreply, select(socket, [])},
      else: {:noreply, select(socket, view(assigns, []))}
  end

  def handle_event("clear_selection", _params, socket), do: {:noreply, select(socket, [])}

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

    case editable(current_scope, fetch_transaction(current_scope, id)) do
      {:ok, transaction, split_of} ->
        row_id = if is_integer(id), do: id, else: String.to_integer(id)

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
        columns: assigns.columns,
        today: assigns.today
      }
    }
  end

  defp focus_id("account"), do: "tx-account"

  defp focus_id(field) when field in ~w(date payee category memo outflow inflow),
    do: "tx-#{field}"

  defp focus_id(_field), do: "tx-payee"

  # A reconciled transaction is unlocked to cleared, so the cleared balance stays as it is.
  defp toggled(:uncleared), do: :cleared
  defp toggled(:cleared), do: :uncleared
  defp toggled(:reconciled), do: :cleared

  defp toggle(set, id), do: if(id in set, do: MapSet.delete(set, id), else: MapSet.put(set, id))

  defp change(socket, id, fun) do
    case find(socket, id) do
      nil -> {:noreply, socket}
      transaction -> socket |> saved(fun.(transaction)) |> noreply()
    end
  end

  defp approve(socket, transactions, params, approved, note \\ "") do
    result =
      Ledger.update_transactions(
        socket.assigns.current_scope,
        transactions,
        %{approved: true},
        confirmed(params)
      )

    socket = if match?({:ok, _}, result), do: approved.(socket), else: socket
    socket |> saved(result, "#{length(transactions)} bestätigt.#{note}") |> noreply()
  end

  defp open_proposals_text(%{assigns: %{proposals: []}}), do: ""

  defp open_proposals_text(%{assigns: %{proposals: [_]}}),
    do: " 1 Zuordnungsvorschlag bleibt offen: Zuordnen oder Trennen."

  defp open_proposals_text(%{assigns: %{proposals: proposals}}),
    do: " #{length(proposals)} Zuordnungsvorschläge bleiben offen: Zuordnen oder Trennen."

  defp decide(socket, id, fun, message) do
    case Enum.find(socket.assigns.proposals, &(Integer.to_string(&1.id) == id)) do
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
    do: Enum.find(socket.assigns.rows, &(Integer.to_string(&1.id) == id))

  defp filter(param), do: Enum.find(Rows.filters(), :all, &(Atom.to_string(&1) == param))

  defp view_paths(assigns) do
    %{
      filters: Map.new(Rows.filters(), &{&1, register_path(assigns, filter: &1)}),
      running: register_path(assigns, running: !assigns.running)
    }
  end

  # With no account taking manual entries there is nothing to book in.
  defp manual_entry?(nil, accounts),
    do: Enum.any?(Map.values(accounts), &Account.takes_entries?/1)

  defp manual_entry?(account, _accounts), do: Account.takes_entries?(account)

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

    base =
      if assigns.account,
        do: ~p"/budget/accounts/#{assigns.account}",
        else: ~p"/budget/accounts/all"

    if params == [], do: base, else: base <> "?" <> Query.encode(params)
  end
end

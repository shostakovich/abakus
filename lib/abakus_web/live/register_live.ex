defmodule AbakusWeb.RegisterLive do
  @moduledoc """
  The register: one account's transactions (`/accounts/:id`) or every account's (`/accounts/all`), newest first,
  below the balances. The view (`filter`), the search (`q`) and the running balance (`running`, one account in the
  full list only) live in the URL; the selection does not.

  Here transactions are approved (one, the selected or all), categorised (the selected), flagged and toggled
  between uncleared and cleared. A change to a reconciled transaction asks in the browser first and then sends
  `reconciled: "confirmed"`, which goes to the Ledger as `reconciled: :confirmed`. Accounts fed by another app offer
  no manual entry.

  Match proposals are not in the register but shown among its rows, waiting like an unapproved transaction, with
  the transaction they match: "Zuordnen" merges them, "Trennen" keeps the import as a transaction of its own, and
  "Alle Zuordnungen übernehmen" in the banner merges all. Approving all leaves them open, as that is a decision of
  its own.

  "Abgleichen" reconciles one account (`Reconcile`): its popover asks whether the balance is right, reconcile mode
  keeps the difference in a banner while transactions are cleared, until it is finished or cancelled.

  The pencil beside the name opens the account form (`AbakusWeb.AccountDialog`); the account shown is the one in
  `account_groups`, so it is as fresh as the sidebar.

  Transactions are edited as in YNAB, without a URL (`TransactionEditor`): a click selects a row, a click into a
  cell of a selected row opens the row for editing, "Buchung" adds an empty row on top; one row at a time. Phones
  open a sheet from a card or the "+ Buchung" button instead. The counterpart of a split's transfer opens its
  split. The selection bar approves, categorises and deletes the selected transactions.
  """
  use AbakusWeb, :live_view

  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Transaction}
  alias AbakusWeb.{AccountGroups, CategoryOptions, Format}
  alias AbakusWeb.RegisterLive.{Balances, Components, Reconcile, Rows, TransactionEditor}
  alias Plug.Conn.Query

  import TransactionEditor, only: [confirmed: 1]

  @flags Ecto.Enum.dump_values(Abakus.Ledger.Transaction, :flag)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={if @account, do: :accounts, else: :all_accounts}
      account_id={@account && @account.id}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <div id="register">
        <Components.banner
          :if={@unapproved != [] or @proposals != []}
          transactions={@unapproved}
          proposals={@proposals}
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
          <Reconcile.popover :if={@account && !@reconciling} state={@reconcile} />
        </div>
        <Components.meta account={@account} />
        <Reconcile.banner :if={@reconciling} mode={@reconciling} />
        <Components.balances account={@account} balances={@balances} />
        <Components.toolbar
          account={@account}
          manual={@manual}
          filter={@filter}
          query={@query}
          running={@running}
          running_shown={@running_balances != nil}
          paths={@paths}
        />
        <Components.bulk
          :if={MapSet.size(@selected) > 0 and !@editor}
          selected={Enum.filter(@rows, &(&1.id in @selected))}
          categories={@categories}
        />
        <Components.table
          rows={@rows}
          proposals={@shown_proposals}
          accounts={@accounts}
          columns={@columns}
          selected={@selected}
          flag_menu={@flag_menu}
          running={@running_balances}
          editor={@editor && @editor.layout == :row && @editor}
          empty={empty_text(@transactions, @proposals)}
        />
        <Components.cards
          rows={@rows}
          proposals={@shown_proposals}
          accounts={@accounts}
          all={is_nil(@account)}
          empty={empty_text(@transactions, @proposals)}
        />
        <Components.legend :if={!(@account && @account.fed_by == :portfolio)} />
        <button
          :if={@manual && !@editor}
          id="new-transaction-fab"
          type="button"
          class="btn btn-primary btn-lg rounded-pill shadow-lg d-inline-flex d-md-none align-items-center gap-1 app-fab"
          phx-click="new"
          phx-value-layout="sheet"
        >
          <.icon name="plus" /> Buchung
        </button>
      </div>
      <.live_component
        :if={@editor && @editor.layout == :sheet}
        module={TransactionEditor}
        {@editor.assigns}
      />
    </Layouts.app>
    """
  end

  defp empty_text([], []), do: "Noch keine Buchungen."
  defp empty_text(_transactions, _proposals), do: "Keine Buchungen in dieser Ansicht."

  @impl true
  def mount(_params, _session, socket) do
    connect = get_connect_params(socket) || %{}

    {:ok,
     assign(socket,
       today: Format.today(connect["today"]),
       scope: nil,
       editor: nil,
       selected: MapSet.new(),
       flag_menu: nil,
       reconcile: nil,
       reconciling: nil
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
     |> assign_rows()}
  end

  defp scope(%{"id" => id}), do: {:account, id}
  defp scope(_params), do: :all

  defp fetch_transaction(id) when is_integer(id), do: Ledger.get_transaction(id)

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
    |> assign(scope: :all, account: nil, selected: MapSet.new(), editor: nil)
    |> assign(reconcile: nil, reconciling: nil)
    |> load_transactions()
  end

  defp load(socket, {:account, id} = scope) do
    account = Ledger.get_account!(id)

    socket
    |> assign(scope: scope, account: account, selected: MapSet.new(), editor: nil)
    |> assign(reconcile: nil, reconciling: nil)
    |> load_transactions()
  end

  defp load_transactions(socket) do
    scope = socket.assigns.account || :all

    assign(socket,
      transactions: Ledger.list_transactions(scope),
      proposals: Ledger.list_match_proposals(scope)
    )
  end

  defp assign_rows(socket) do
    %{transactions: transactions, filter: filter, query: query} = socket.assigns
    account_rows = AccountGroups.rows(socket.assigns.account_groups)
    accounts = Map.new(account_rows, &{&1.account.id, &1.account})
    account = socket.assigns.account && Map.fetch!(accounts, socket.assigns.account.id)

    socket =
      assign(socket, account: account, page_title: (account && account.name) || "Alle Konten")

    rows = transactions |> Rows.filter(filter) |> Rows.search(query)
    shown_proposals = socket.assigns.proposals |> Rows.filter(filter) |> Rows.search(query)
    balances = balances(account, account_rows)
    running = running_balances(socket.assigns, rows, balances)
    columns = Components.columns(account, running != nil)

    assign(socket,
      rows: rows,
      shown_proposals: shown_proposals,
      accounts: accounts,
      manual: manual_entry?(account, accounts),
      columns: columns,
      editor: follow_rows(socket.assigns.editor, rows, accounts, columns),
      categories: CategoryOptions.build(socket.assigns.today),
      balances: balances,
      unapproved: Enum.reject(transactions, & &1.approved),
      running_balances: running,
      paths: view_paths(Map.put(socket.assigns, :accounts, accounts)),
      selected: MapSet.intersection(socket.assigns.selected, MapSet.new(rows, & &1.id))
    )
  end

  # The edited row goes when the view or search leaves it out; the editor sees the columns as they are now.
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
        transaction,
        %{cleared: toggled(transaction.cleared)},
        confirmed(params)
      )
    end)
  end

  def handle_event("approve", %{"id" => id} = params, socket) do
    change(socket, id, &Ledger.update_transaction(&1, %{approved: true}, confirmed(params)))
  end

  def handle_event("approve_all", params, socket) do
    approve(socket, socket.assigns.unapproved, params, & &1, open_proposals_text(socket))
  end

  def handle_event("accept_match", %{"id" => id} = params, socket) do
    decide(socket, id, &Ledger.accept_match(&1, confirmed(params)), "Zugeordnet.")
  end

  def handle_event("reject_match", %{"id" => id}, socket) do
    decide(socket, id, &Ledger.reject_match/1, "Getrennt und als eigene Buchung bestätigt.")
  end

  def handle_event("accept_all_matches", params, socket) do
    proposals = socket.assigns.proposals

    socket
    |> saved(
      Ledger.accept_matches(proposals, confirmed(params)),
      "#{length(proposals)} zugeordnet."
    )
    |> noreply()
  end

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
          else: {:noreply, assign(socket, :selected, MapSet.new([id]))}
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
    case selected(socket.assigns) do
      [] ->
        {:noreply, socket}

      transactions ->
        transactions = Enum.uniq_by(Enum.map(transactions, &deletable/1), & &1.id)

        case Ledger.delete_transactions(transactions, confirmed(params)) do
          {:ok, deleted} ->
            socket
            |> assign(:selected, MapSet.new())
            |> saved({:ok, deleted}, deleted_text(length(deleted)))
            |> noreply()

          {:error, changeset} ->
            socket
            |> put_flash(:error, "Nicht gelöscht: #{TransactionEditor.error_message(changeset)}")
            |> refresh()
            |> noreply()
        end
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

  def handle_event(
        "reconcile_open",
        _params,
        %{assigns: %{account: %Account{} = account}} = socket
      ),
      do: {:noreply, assign(socket, :reconcile, ask(account, socket.assigns.today))}

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

  # The popover's question: about the newest bank balance and the cleared balance up to its date, else about the
  # cleared balance as it is today.
  defp ask(account, today) do
    bank =
      case Ledger.latest_bank_balance(account) do
        nil -> Reconcile.bank(Ledger.cleared_balance(account, today), today)
        stored -> Reconcile.bank(stored)
      end

    account |> reconcile_mode(bank) |> Map.merge(%{step: :ask, error: nil})
  end

  defp start_reconciling(socket, bank) do
    assign(socket, reconcile: nil, reconciling: reconcile_mode(socket.assigns.account, bank))
  end

  defp reconcile(socket, bank, opts) do
    socket = assign(socket, reconcile: nil)

    case Ledger.reconcile(socket.assigns.account, bank, opts) do
      {:ok, result} ->
        socket |> assign(:reconciling, nil) |> saved({:ok, result}, Reconcile.done_text(result))

      {:error, {:difference, difference}} ->
        socket |> put_flash(:error, Reconcile.refused_text(difference)) |> refresh()

      {:error, changeset} ->
        saved(socket, {:error, changeset})
    end
  end

  defp deleted_text(1), do: "Buchung gelöscht."
  defp deleted_text(count), do: "#{count} Buchungen gelöscht."

  # The counterpart of a split's transfer goes with its split, as it is edited there.
  defp deletable(%Transaction{transfer_subtransaction_id: id} = transaction)
       when not is_nil(id) do
    %{transfer_subtransaction: %{transaction_id: split_id}} =
      Ledger.get_transaction!(transaction.id)

    %Transaction{id: split_id}
  end

  defp deletable(transaction), do: transaction

  defp open_editor(socket, id, layout, field) do
    case editable(fetch_transaction(id)) do
      {:ok, transaction, split_of} ->
        row_id = if is_integer(id), do: id, else: String.to_integer(id)

        socket
        |> assign(
          :selected,
          if(layout == :row, do: MapSet.new([row_id]), else: socket.assigns.selected)
        )
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

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(flag), do: flag

  defp toggle(set, id), do: if(id in set, do: MapSet.delete(set, id), else: MapSet.put(set, id))

  defp change(socket, id, fun) do
    case find(socket, id) do
      nil -> {:noreply, socket}
      transaction -> socket |> saved(fun.(transaction)) |> noreply()
    end
  end

  defp approve(socket, transactions, params, approved, note \\ "") do
    result = Ledger.update_transactions(transactions, %{approved: true}, confirmed(params))
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
      |> put_flash(:error, "Nicht geändert: #{TransactionEditor.error_message(changeset)}")
      |> refresh()

  defp refresh(socket) do
    socket
    |> assign(:account_groups, AccountGroups.load())
    |> load_transactions()
    |> assign_rows()
    |> update(:reconciling, &follow_cleared(&1, socket.assigns.account))
  end

  # Reconcile mode's cleared balance follows every change.
  defp follow_cleared(nil, _account), do: nil
  defp follow_cleared(%{bank: bank}, account), do: reconcile_mode(account, bank)

  defp reconcile_mode(account, bank),
    do: %{bank: bank, cleared: Ledger.cleared_balance(account, bank.through)}

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

  # With no account taking manual entries there is nothing to book in.
  defp manual_entry?(nil, accounts),
    do: Enum.any?(Map.values(accounts), &Account.takes_entries?/1)

  defp manual_entry?(account, _accounts), do: Account.takes_entries?(account)

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
end

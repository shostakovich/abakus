defmodule AbakusWeb.RegisterLive.Components do
  @moduledoc """
  The parts of the register: the header's meta line, balances and toolbar, the selection bar, the table on desktops
  and the list on phones, both with the match proposals among the transactions. A click into a selected row (on phones
  a list row) opens the transaction editor. Actions that change a reconciled transaction ask in the confirmation
  dialog first and send `reconciled: "confirmed"`.
  """
  use AbakusWeb, :html

  alias Abakus.Format
  alias Abakus.Ledger.{Account, Payee, Subtransaction, Transaction}
  alias Abakus.Money
  alias Abakus.Names
  alias AbakusWeb.{AccountGroups, CategoryOptions}
  alias AbakusWeb.RegisterLive.{Rows, TransactionEditor}

  @feeds %{
    portfolio: "Wert kommt aus dem Depot",
    shared_expenses: "Buchungen kommen aus der Kasse"
  }

  attr :account, Account, default: nil

  @doc "The line below the title: the account's kind, closed, last reconciled (with the lock) and note."
  def meta(assigns) do
    assigns = assign(assigns, :parts, meta_parts(assigns.account))

    ~H"""
    <span id="register-meta" class="inline-flex flex-wrap items-center gap-x-1">
      <%= for {part, index} <- Enum.with_index(@parts) do %>
        <span :if={index > 0} aria-hidden="true">·</span>
        <span :if={is_binary(part)}>{part}</span>
        <span :if={match?({:reconciled, _date}, part)} class="inline-flex items-center gap-1">
          <.icon name="lock" class="size-3.5" />Abgeglichen am {Format.date(elem(part, 1))}
        </span>
      <% end %>
    </span>
    """
  end

  defp meta_parts(nil), do: ["Budget- und Tracking-Konten"]

  defp meta_parts(account) do
    Enum.filter(
      [
        AccountGroups.kind_label(account.kind),
        account.closed && "Geschlossen",
        account.last_reconciled_at && {:reconciled, account.last_reconciled_at},
        account.note
      ],
      & &1
    )
  end

  attr :account, Account, default: nil
  attr :balances, :map, required: true

  attr :reconciling, :boolean,
    default: false,
    doc: "the difference animates then, not the balance"

  @doc """
  The header's second row. One account: Gebucht + Vorgemerkt = Arbeitssaldo, or for a depot only its value. All
  accounts: that equation for the budget accounts, then tracking and the total. Phones get one compact line.
  """
  def balances(assigns) do
    ~H"""
    <div
      id="register-balances"
      class="app-reg-row flex flex-wrap items-center gap-x-6 gap-y-2 max-md:hidden"
    >
      <%= cond do %>
        <% portfolio?(@account) -> %>
          <.figure
            id="balance-working"
            value={@balances.working}
            label="Wert laut Depot"
            animate={!@reconciling}
          />
        <% @account -> %>
          <.equation balances={@balances} animate={!@reconciling} />
        <% true -> %>
          <.equation balances={@balances.budget} label="Budgetkonten" animate />
          <span class="self-stretch border-s border-base-content/10" aria-hidden="true"></span>
          <.figure id="balance-tracking" value={@balances.tracking} label="Tracking" />
          <span class="self-stretch border-s border-base-content/10" aria-hidden="true"></span>
          <.figure id="balance-total" value={@balances.total} label="Gesamt" />
      <% end %>
    </div>
    <div
      id="register-balances-line"
      class={["app-reg-row app-reg-line flex md:hidden", !@account && "app-reg-line-all"]}
    >
      <%= cond do %>
        <% portfolio?(@account) -> %>
          <.line_figure value={@balances.working} label="Wert laut Depot" />
        <% @account -> %>
          <.line_figure value={@balances.cleared} label="Gebucht" />
          <.line_figure op="+" value={@balances.uncleared} label="Vorgemerkt" tone={false} />
          <.line_figure op="=" value={@balances.working} label="Arbeitssaldo" />
        <% true -> %>
          <.line_figure value={@balances.budget.working} label="Budgetkonten" />
          <.line_figure value={@balances.tracking} label="Tracking" />
          <.line_figure value={@balances.total} label="Gesamt" />
      <% end %>
    </div>
    """
  end

  defp portfolio?(account), do: match?(%Account{fed_by: :portfolio}, account)

  attr :balances, :map, required: true
  attr :animate, :boolean, default: false

  attr :label, :any,
    default: nil,
    doc: "what the working balance stands for, else \"Arbeitssaldo\""

  defp equation(assigns) do
    ~H"""
    <div class="flex flex-wrap items-start gap-x-4 gap-y-2">
      <.figure id="balance-cleared" value={@balances.cleared} label="Gebucht" state={:cleared} />
      <.figure
        id="balance-uncleared"
        op="+"
        value={@balances.uncleared}
        label="Vorgemerkt"
        state={:uncleared}
        tone={false}
      />
      <.figure
        id="balance-working"
        op="="
        value={@balances.working}
        label={@label || "Arbeitssaldo"}
        animate={@animate}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :op, :string, default: nil
  attr :value, :integer, required: true
  attr :label, :string, required: true
  attr :state, :atom, default: nil, doc: "the cleared state whose icon goes before the label"
  attr :animate, :boolean, default: false
  attr :tone, :any, default: :negative

  defp figure(assigns) do
    ~H"""
    <div class="flex items-start gap-3">
      <span :if={@op} class="text-lg text-base-content/70" aria-hidden="true">{@op}</span>
      <div class="flex flex-col">
        <.amount id={@id} value={@value} size={:lg} tone={@tone} animate={@animate} />
        <span class="inline-flex items-center gap-1 text-sm text-base-content/70">
          <.state_icon :if={@state} state={@state} />{@label}
        </span>
      </div>
    </div>
    """
  end

  attr :op, :string, default: nil
  attr :value, :integer, required: true
  attr :label, :string, required: true
  attr :tone, :any, default: :negative

  defp line_figure(assigns) do
    ~H"""
    <span :if={@op} class="text-base-content/70" aria-hidden="true">{@op}</span>
    <span class="app-reg-figure">
      <.amount value={@value} tone={@tone} class="font-semibold" />
      <span class="truncate text-xs text-base-content/70">{@label}</span>
    </span>
    """
  end

  attr :state, :atom, required: true

  defp state_icon(%{state: :cleared} = assigns),
    do: ~H|<.icon name="circle-check" class="app-state-cleared" />|

  defp state_icon(%{state: :uncleared} = assigns),
    do: ~H|<.icon name="circle" class="app-state-uncleared" />|

  defp state_icon(%{state: :reconciled} = assigns),
    do: ~H|<.icon name="lock" class="app-state-reconciled" />|

  attr :account, Account, default: nil

  attr :manual, :boolean, required: true, doc: "whether \"Buchung\" adds a transaction here"

  attr :unapproved, :list, required: true
  attr :proposals, :list, required: true
  attr :filter, :atom, required: true
  attr :query, :string, required: true
  attr :running, :boolean, required: true
  attr :running_shown, :boolean, required: true
  attr :paths, :map, required: true

  @doc """
  The header's third row: "Buchung", "Datei-Import" and what waits ("Alle bestätigen" with the count, "Alle
  zuordnen"), then the view menu and the search. Phones keep the search and the menu, which takes the rest; the
  floating button adds a transaction there.
  """
  def toolbar(assigns) do
    ~H"""
    <div id="register-toolbar" class="app-reg-row">
      <div class="app-reg-toolbar">
        <div class="app-reg-actions flex max-md:hidden">
          <.button
            :if={@manual}
            id="new-transaction"
            variant={:ghost}
            size={:sm}
            icon="plus"
            phx-click="new"
            phx-value-layout="row"
          >
            Buchung
          </.button>
          <.button
            :if={@manual}
            id="file-import"
            variant={:ghost}
            size={:sm}
            icon="file-text"
            navigate={~p"/budget/import"}
          >
            Datei-Import
          </.button>
          <.button
            :if={@unapproved != []}
            id="approve-all"
            variant={:ghost}
            size={:sm}
            icon="check"
            aria-label={"Alle #{length(@unapproved)} bestätigen"}
            phx-click="approve_all"
            {confirm(@unapproved)}
          >
            Alle bestätigen
            <.badge id="approve-all-count" tone={:primary} style={:plain}>
              {length(@unapproved)}
            </.badge>
          </.button>
          <.button
            :if={@proposals != []}
            id="accept-all-matches"
            variant={:ghost}
            size={:sm}
            icon="link"
            phx-click="accept_all_matches"
            {confirm_merge(@proposals)}
          >
            Alle zuordnen
          </.button>
        </div>
        <div class="app-reg-find">
          <.dropdown
            id="view-menu"
            align={:end}
            variant={:ghost}
            chevron={false}
            trigger_class="btn-sm max-md:btn-square"
          >
            <:trigger>
              <span id="view-toggle" class="max-md:sr-only">{view_label(@filter)}</span>
              <.icon name="chevron-down" class="max-md:hidden" />
              <.icon name="ellipsis-vertical" class="md:hidden" />
            </:trigger>
            <:item
              :if={@manual}
              id="file-import-item"
              icon="file-text"
              navigate={~p"/budget/import"}
              class="md:hidden"
            >
              Datei-Import
            </:item>
            <:item
              :if={@unapproved != []}
              id="approve-all-item"
              icon="check"
              class="md:hidden"
              confirm={question(@unapproved)}
              confirm_text="Der gebuchte Saldo bleibt gleich."
              confirm_label="Ändern"
              on_click={
                JS.push("approve_all",
                  value: if(reconciled(@unapproved) != [], do: %{reconciled: "confirmed"}, else: %{})
                )
              }
            >
              Alle bestätigen ({length(@unapproved)})
            </:item>
            <:item
              :if={@proposals != []}
              id="accept-all-matches-item"
              icon="link"
              class="md:hidden"
              confirm={merge_question(@proposals)}
              confirm_text={merge_text()}
              confirm_label="Zuordnen"
              on_click={
                JS.push("accept_all_matches",
                  value: if(merge_question(@proposals), do: %{reconciled: "confirmed"}, else: %{})
                )
              }
            >
              Alle zuordnen
            </:item>
            <:item
              :for={{filter, label} <- filter_labels()}
              patch={@paths.filters[filter]}
              active={@filter == filter}
            >
              {label}
            </:item>
            <:item :if={@account} id="running-toggle" patch={@paths.running} divider>
              {if @running, do: "Laufenden Saldo ausblenden", else: "Laufenden Saldo zeigen"}
            </:item>
            <:item
              id="memo-toggle"
              on_click={JS.dispatch("abakus:toggle-memo")}
              class="max-md:hidden"
              divider={!@account}
            >
              <span class="app-memo-hide">Memo ausblenden</span><span class="app-memo-show">Memo zeigen</span>
            </:item>
          </.dropdown>
          <form
            id="register-search"
            class="app-reg-search"
            role="search"
            phx-change="search"
            phx-submit="search"
          >
            <.input
              id="register-q"
              type="search"
              name="q"
              value={@query}
              label="Buchungen durchsuchen"
              hide_label
              icon="search"
              placeholder="Suchen"
              class="input-sm"
              phx-debounce="300"
            />
          </form>
        </div>
      </div>
      <p :if={@account && @account.fed_by} id="feed-hint" class="app-reg-hint">
        <.icon name="info" class="shrink-0" />
        {feed_hint(@account)}, keine Buchungen von Hand oder per Datei
      </p>
      <p :if={@account && @running && !@running_shown} id="running-hint" class="app-reg-hint">
        Laufender Saldo nur in „Alle Buchungen“ ohne Suche
      </p>
    </div>
    """
  end

  defp feed_hint(account), do: @feeds[account.fed_by]

  defp filter_labels,
    do: [all: "Alle Buchungen", unapproved: "Zu bestätigen", uncleared: "Vorgemerkt"]

  defp view_label(:all), do: "Ansicht"
  defp view_label(:unapproved), do: "Ansicht: zu bestätigen"
  defp view_label(:uncleared), do: "Ansicht: vorgemerkt"

  attr :selected, :list, required: true
  attr :categories, :list, required: true

  @doc """
  The selection bar as in YNAB: how many are selected (× clears), approve when one of them waits, categorise with
  the category picker, and under "Mehr" delete. Always rendered; it shows while something is selected.
  """
  def bulk(assigns) do
    assigns =
      assign(assigns,
        count: length(assigns.selected),
        waiting: Enum.reject(assigns.selected, & &1.approved),
        options: category_options(assigns.categories)
      )

    ~H"""
    <.selection_bar
      id="bulk"
      count={@count}
      label={if @count == 1, do: "1 Buchung", else: "%{count} Buchungen"}
      on_clear="clear_selection"
    >
      <.button
        :if={@waiting != []}
        id="approve-selected"
        variant={:ghost}
        size={:sm}
        icon="check"
        phx-click="approve_selected"
        {confirm(@waiting)}
      >
        Bestätigen
      </.button>
      <.popover
        :if={@count > 0}
        id="categorise"
        title="Kategorisieren"
        position={:top}
        variant={:ghost}
        trigger_class="btn-sm"
        class="w-80"
      >
        <:trigger>Kategorisieren</:trigger>
        <form
          id="categorise-form"
          class="grid gap-3"
          phx-submit={JS.push("categorise_selected") |> hide_popover("categorise")}
        >
          <input
            :if={reconciled(@selected) != []}
            type="hidden"
            name="reconciled"
            value="confirmed"
          />
          <.combobox
            id="categorise-category"
            name="category_id"
            value=""
            label="Kategorie"
            hide_label
            options={@options}
            placeholder="Kategorie suchen"
            autofocus
          >
            <:option :let={option}>
              <span class="min-w-0 flex-1 truncate">{option.name}</span>
              <.amount value={option.available} tone />
            </:option>
          </.combobox>
          <.button
            id="categorise-submit"
            type="submit"
            size={:sm}
            variant={:primary}
            {confirm(@selected, [])}
          >
            Kategorisieren
          </.button>
        </form>
      </.popover>
      <.dropdown
        id="bulk-more"
        align={:end}
        position={:top}
        variant={:ghost}
        chevron={false}
        trigger_class="btn-sm"
      >
        <:trigger><.icon name="ellipsis" /> Mehr</:trigger>
        <:item
          id="delete-selected"
          icon="trash-2"
          danger
          confirm={delete_question(@selected)}
          on_click={
            JS.push("delete_selected",
              value: if(locked(@selected) != [], do: %{reconciled: "confirmed"}, else: %{})
            )
          }
        >
          Löschen
        </:item>
      </.dropdown>
    </.selection_bar>
    """
  end

  defp category_options(categories) do
    for group <- categories do
      {group.name,
       for(
         option <- group.options,
         do: %{
           label: option.text,
           value: option.id,
           name: option.name,
           available: option.available
         }
       )}
    end
  end

  attr :rows, :list, required: true
  attr :proposals, :list, required: true, doc: "the match proposals shown among the rows"
  attr :accounts, :map, required: true
  attr :columns, :map, required: true, doc: "`%{all, category, running, count}`, see `columns/2`"
  attr :selected, :any, required: true
  attr :running, :map, default: nil

  attr :editor, :any,
    required: true,
    doc: "the transaction editor's assigns while a row is edited"

  attr :empty, :string, required: true
  attr :empty_hint, :string, default: nil

  @doc """
  The register on desktops, as in YNAB: a click selects a row, a click into a cell of a selected row opens it for
  editing there, with the cursor in that cell. Each transaction is a `<tbody>` of its own, so a split keeps its
  subtransactions below it, collapsible, and the editor (`TransactionEditor`) takes its place while it is edited.
  A match proposal is no row to select or edit: below it is what it matches, with "Zuordnen" and "Trennen".
  """
  def table(assigns) do
    assigns =
      assign(assigns,
        all_selected:
          assigns.rows != [] and MapSet.size(assigns.selected) == length(assigns.rows),
        edited: assigns.editor && assigns.editor.row_id
      )

    ~H"""
    <div class="app-reg-wrap max-md:hidden border-y border-base-content/10">
      <table
        id="register-table"
        class={[
          "table setzkasten-table-dense tabular-nums app-reg",
          @columns.all && "app-reg-all",
          !@columns.category && "app-reg-nocat",
          @columns.running && "app-reg-running"
        ]}
      >
        <colgroup>
          <col class="app-col-pick" />
          <col class="app-col-date" />
          <col :if={@columns.all} class="app-col-konto" />
          <col class="app-col-payee" />
          <col :if={@columns.category} class="app-col-cat" />
          <col class="app-col-memo" />
          <col class="app-col-out" />
          <col class="app-col-in" />
          <col :if={@columns.running} class="app-col-run" />
          <col class="app-col-ok" />
          <col class="app-col-c" />
        </colgroup>
        <thead>
          <tr>
            <th class="app-pick">
              <input
                id="select-all"
                type="checkbox"
                class="checkbox checkbox-xs"
                checked={@all_selected}
                phx-click="select_all"
                aria-label="Alle auswählen"
              />
            </th>
            <th class="app-date-col">Datum</th>
            <th :if={@columns.all} class="app-konto">Konto</th>
            <th class="app-payee">Empfänger</th>
            <th :if={@columns.category} class="app-catcol">Kategorie</th>
            <th class="app-memo-col">Memo</th>
            <th class="text-end app-out">Ausgang</th>
            <th class="text-end app-in">Eingang</th>
            <th :if={@columns.running} class="text-end app-run">Saldo</th>
            <th class="app-ok-col"><span class="sr-only">Bestätigen</span></th>
            <th class="app-c-col">
              <span class="sr-only">Gebucht</span><.icon name="check" />
            </th>
          </tr>
        </thead>
        <.live_component :if={@edited == :new} module={TransactionEditor} {@editor.assigns} />
        <.entry
          :for={transaction <- Rows.with_proposals(@rows, @proposals)}
          :key={transaction.id}
          transaction={transaction}
          accounts={@accounts}
          columns={@columns}
          selected={transaction.id in @selected}
          running={@running && @running[transaction.id]}
          editor={@edited == transaction.id && @editor}
        />
        <tbody :if={@rows == [] and @proposals == []}>
          <tr>
            <td colspan={@columns.count}>
              <.empty title={@empty} hint={@empty_hint} class="py-4" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc "The table's columns: the account column in all accounts, none for categories in a tracking account."
  def columns(account, running) do
    all = is_nil(account)
    category = all or Account.budget_account?(account)
    count = 8 + Enum.count([all, category, running], & &1)
    %{all: all, category: category, running: running, count: count}
  end

  attr :transaction, :map, required: true
  attr :accounts, :map, required: true
  attr :columns, :map, required: true
  attr :selected, :boolean, required: true

  attr :running, :integer,
    default: nil,
    doc: "the balance after it, while the running balance shows"

  attr :editor, :any, required: true, doc: "the editor while this row is edited, else false"

  defp entry(%{transaction: %{matched_transaction_id: id}} = assigns) when not is_nil(id),
    do: ~H"<.proposal_row proposal={@transaction} accounts={@accounts} columns={@columns} />"

  defp entry(%{editor: %{assigns: _}} = assigns),
    do: ~H"<.live_component module={TransactionEditor} {@editor.assigns} />"

  defp entry(assigns) do
    ~H"""
    <.row
      transaction={@transaction}
      accounts={@accounts}
      columns={@columns}
      selected={@selected}
      running={@running}
    />
    """
  end

  attr :transaction, :map, required: true
  attr :accounts, :map, required: true
  attr :columns, :map, required: true
  attr :selected, :boolean, required: true
  attr :running, :integer, default: nil

  defp row(assigns) do
    ~H"""
    <tbody id={"tx-#{@transaction.id}-rows"} class={["app-tx", @selected && "is-selected"]}>
      <tr
        id={"tx-#{@transaction.id}"}
        class={["app-tx-main", !@transaction.approved && "app-unapproved"]}
      >
        <td class="app-pick">
          <input
            id={"tx-#{@transaction.id}-select"}
            type="checkbox"
            class="checkbox checkbox-xs"
            checked={@selected}
            phx-click="select"
            phx-value-id={@transaction.id}
            aria-label="Buchung auswählen"
          />
        </td>
        <td {cell(@transaction, "date")}>
          <span class="app-wide">{Format.date(@transaction.date)}</span>
          <span class="app-short">{Format.date(@transaction.date, year: false)}</span>
        </td>
        <td
          :if={@columns.all}
          class="app-konto"
          title={@accounts[@transaction.account_id].name}
          {cell(@transaction, "account")}
        >
          <.account_cell account={@accounts[@transaction.account_id]} />
        </td>
        <td class="app-payee" {cell(@transaction, "payee")}>
          {payee(@transaction, @accounts)}<span
            :if={payee(@transaction, @accounts) == ""}
            class="text-base-content/70"
          >Ohne Empfänger</span>
        </td>
        <td :if={@columns.category} class="app-catcol" {cell(@transaction, "category")}>
          <button
            :if={@transaction.subtransactions != []}
            id={"tx-#{@transaction.id}-parts"}
            type="button"
            class="app-parts-toggle"
            aria-label="Teile ein- oder ausklappen"
            phx-click={JS.toggle_class("is-collapsed", to: "#tx-#{@transaction.id}-rows")}
          >
            <.icon name="chevron-down" />
          </button>
          <.category transaction={@transaction} accounts={@accounts} />
        </td>
        <td class="text-base-content/70 app-memo-col" {cell(@transaction, "memo")}>
          {@transaction.memo}
        </td>
        <td class="text-end app-out" {cell(@transaction, "outflow")}>
          {outflow(@transaction.amount)}
        </td>
        <td class="text-end app-in" {cell(@transaction, "inflow")}>
          {inflow(@transaction.amount)}
        </td>
        <td :if={@running} class="text-end text-base-content/70 app-run">
          {Money.amount(@running)}
        </td>
        <td class="app-ok-col">
          <.approve
            :if={!@transaction.approved}
            id={"tx-#{@transaction.id}-approve"}
            transaction={@transaction}
            accounts={@accounts}
          />
        </td>
        <td class="app-c-col">
          <.cleared id={"tx-#{@transaction.id}-cleared"} transaction={@transaction} />
        </td>
      </tr>
      <tr
        :for={{part, index} <- Enum.with_index(@transaction.subtransactions)}
        id={"tx-#{@transaction.id}-part-#{index}"}
        class="app-part"
      >
        <td></td>
        <td {cell(@transaction, "date")}></td>
        <td :if={@columns.all} {cell(@transaction, "account")}></td>
        <td class="app-payee" {cell(@transaction, "payee")}>
          {payee(part, @accounts)}
        </td>
        <td :if={@columns.category} class="app-catcol" {cell(@transaction, "category")}>
          {category_text(part, @accounts)}
        </td>
        <td class="app-memo-col" {cell(@transaction, "memo")}>
          {part.memo}
        </td>
        <td class="text-end app-out" {cell(@transaction, "outflow")}>{outflow(part.amount)}</td>
        <td class="text-end app-in" {cell(@transaction, "inflow")}>{inflow(part.amount)}</td>
        <td :if={@running}></td>
        <td></td>
        <td></td>
      </tr>
    </tbody>
    """
  end

  attr :proposal, Transaction, required: true
  attr :accounts, :map, required: true
  attr :columns, :map, required: true

  defp proposal_row(assigns) do
    ~H"""
    <tbody id={"proposal-#{@proposal.id}-rows"} class="app-tx">
      <tr id={"proposal-#{@proposal.id}"} class="app-tx-main app-unapproved">
        <td class="app-pick"></td>
        <td>
          <span class="app-wide">{Format.date(@proposal.date)}</span>
          <span class="app-short">{Format.date(@proposal.date, year: false)}</span>
        </td>
        <td :if={@columns.all} class="app-konto" title={@accounts[@proposal.account_id].name}>
          <.account_cell account={@accounts[@proposal.account_id]} />
        </td>
        <td class="app-payee">
          {payee(@proposal, @accounts)}<span
            :if={payee(@proposal, @accounts) == ""}
            class="text-base-content/70"
          >Ohne Empfänger</span>
        </td>
        <td :if={@columns.category} class="app-catcol"></td>
        <td class="text-base-content/70 app-memo-col">{@proposal.memo}</td>
        <td class="text-end app-out">{outflow(@proposal.amount)}</td>
        <td class="text-end app-in">{inflow(@proposal.amount)}</td>
        <td :if={@columns.running}></td>
        <td></td>
        <td></td>
      </tr>
      <tr id={"proposal-#{@proposal.id}-match"} class="app-actrow app-unapproved">
        <td></td>
        <td colspan={@columns.count - 1}>
          <div class="flex flex-wrap items-center gap-2">
            <span class="flex items-center gap-1 text-base-content/70">
              <.icon name="link" />{match_text(@proposal.matched_transaction, @accounts)}
            </span>
            <.button
              id={"proposal-#{@proposal.id}-accept"}
              size={:sm}
              phx-click="accept_match"
              phx-value-id={@proposal.id}
              {confirm_merge([@proposal])}
            >
              Zuordnen
            </.button>
            <.button
              id={"proposal-#{@proposal.id}-reject"}
              size={:sm}
              phx-click="reject_match"
              phx-value-id={@proposal.id}
            >
              Trennen
            </.button>
          </div>
        </td>
      </tr>
    </tbody>
    """
  end

  @doc "What a match proposal says about the transaction it matches, `accounts` by id naming transfers."
  def match_text(matched, accounts) do
    case payee(matched, accounts) do
      "" -> "passt zu Buchung vom #{Format.date(matched.date)}"
      payee -> "passt zu Buchung vom #{Format.date(matched.date)} · #{payee}"
    end
  end

  # A cell that selects its row, or opens the selected row for editing in that cell.
  defp cell(transaction, field),
    do: ["phx-click": "row_click", "phx-value-id": transaction.id, "phx-value-field": field]

  attr :rows, :list, required: true
  attr :proposals, :list, required: true
  attr :accounts, :map, required: true
  attr :all, :boolean, required: true
  attr :empty, :string, required: true
  attr :empty_hint, :string, default: nil

  @doc """
  Phones: one row per transaction, as on a bank statement, which opens the transaction sheet; one waiting for approval
  has its ✓ in front, the others their cleared state. A match proposal says what it matches, with "Zuordnen" and
  "Trennen" in its menu.
  """
  def cards(assigns) do
    ~H"""
    <.list id="register-cards" class="md:hidden">
      <.card_entry
        :for={transaction <- Rows.with_proposals(@rows, @proposals)}
        :key={transaction.id}
        transaction={transaction}
        accounts={@accounts}
        all={@all}
      />
      <li :if={@rows == [] and @proposals == []} class="px-4">
        <.empty title={@empty} hint={@empty_hint} />
      </li>
    </.list>
    """
  end

  attr :transaction, Transaction, required: true
  attr :accounts, :map, required: true
  attr :all, :boolean, required: true

  defp card_entry(assigns) do
    ~H"""
    <.list_row
      :if={@transaction.matched_transaction_id}
      id={"proposal-card-#{@transaction.id}"}
      title={title(@transaction, @accounts)}
      trailing_on_phone={:title}
      class="app-unapproved-item"
    >
      <:leading><.icon name="link" class="size-5 text-base-content/70" /></:leading>
      <:meta>
        {join_meta([
          Format.date(@transaction.date, year: false),
          if(@all, do: @accounts[@transaction.account_id].name),
          match_text(@transaction.matched_transaction, @accounts)
        ])}
      </:meta>
      <:trailing><.signed amount={@transaction.amount} /></:trailing>
      <:action
        id={"proposal-card-#{@transaction.id}-accept"}
        label="Zuordnen"
        icon="link"
        on_click={decision("accept_match", @transaction)}
        confirm={merge_question([@transaction])}
        confirm_text={merge_text()}
        confirm_label="Zuordnen"
      />
      <:action
        id={"proposal-card-#{@transaction.id}-reject"}
        label="Trennen"
        icon="x"
        on_click={JS.push("reject_match", value: %{id: to_string(@transaction.id)})}
      />
    </.list_row>
    <.list_row
      :if={!@transaction.matched_transaction_id}
      id={"tx-card-#{@transaction.id}"}
      on_click={JS.push("edit", value: %{id: to_string(@transaction.id)})}
      trailing_on_phone={:title}
      class={!@transaction.approved && "app-unapproved-item"}
    >
      <span class={!@transaction.approved && "font-semibold"}>{title(@transaction, @accounts)}</span>
      <:leading>
        <.approve
          :if={!@transaction.approved}
          id={"tx-card-#{@transaction.id}-approve"}
          transaction={@transaction}
          accounts={@accounts}
        />
        <.cleared
          :if={@transaction.approved}
          id={"tx-card-#{@transaction.id}-cleared"}
          transaction={@transaction}
        />
      </:leading>
      <:meta>
        {join_meta([
          Format.date(@transaction.date, year: false),
          if(@all, do: @accounts[@transaction.account_id].name),
          category_text(@transaction, @accounts),
          @transaction.memo
        ])}
      </:meta>
      <:trailing><.signed amount={@transaction.amount} /></:trailing>
    </.list_row>
    """
  end

  defp title(transaction, accounts) do
    case payee(transaction, accounts) do
      "" -> "Ohne Empfänger"
      payee -> payee
    end
  end

  defp decision(event, proposal) do
    value = %{id: to_string(proposal.id)}

    value =
      if merge_question([proposal]), do: Map.put(value, :reconciled, "confirmed"), else: value

    JS.push(event, value: value)
  end

  def legend(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-x-4 gap-y-1 pt-3 text-sm text-base-content/70">
      <span class="inline-flex items-center gap-1">
        <.state_icon state={:uncleared} /> vorgemerkt
      </span>
      <span class="inline-flex items-center gap-1">
        <.state_icon state={:cleared} /> gebucht
      </span>
      <span class="inline-flex items-center gap-1">
        <.state_icon state={:reconciled} /> abgeglichen, gesperrt
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :transaction, :map, required: true

  defp cleared(%{transaction: %{cleared: :reconciled}} = assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="app-clear"
      title="Abgeglichen"
      aria-label="Abgeglichen, entsperren"
      aria-haspopup="dialog"
      phx-click={
        show_confirm(
          %JS{},
          "confirm-delete",
          "Diese Buchung ist abgeglichen. Entsperren?",
          JS.push("toggle_cleared",
            value: %{id: to_string(@transaction.id), reconciled: "confirmed"}
          ),
          text: "Sie ist danach gebucht, aber nicht mehr gesperrt.",
          label: "Entsperren"
        )
      }
    >
      <.state_icon state={:reconciled} />
    </button>
    """
  end

  defp cleared(assigns) do
    assigns = assign(assigns, :cleared?, assigns.transaction.cleared == :cleared)

    ~H"""
    <button
      id={@id}
      type="button"
      class="app-clear"
      title={if @cleared?, do: "Gebucht", else: "Vorgemerkt"}
      aria-label={if @cleared?, do: "Gebucht, umschalten", else: "Vorgemerkt, umschalten"}
      phx-click="toggle_cleared"
      phx-value-id={@transaction.id}
    >
      <.state_icon state={if @cleared?, do: :cleared, else: :uncleared} />
    </button>
    """
  end

  attr :id, :string, required: true
  attr :transaction, :map, required: true
  attr :accounts, :map, required: true

  defp approve(assigns) do
    ~H"""
    <.tooltip id={"#{@id}-tip"} text="Bestätigen" placement={:left}>
      <.button
        id={@id}
        size={:sm}
        variant={:ghost}
        icon="check"
        icon_only
        label={"#{title(@transaction, @accounts)} bestätigen"}
        class="app-approve"
        phx-click="approve"
        phx-value-id={@transaction.id}
        {confirm([@transaction])}
      />
    </.tooltip>
    """
  end

  attr :account, Account, required: true

  defp account_cell(assigns) do
    assigns = assign(assigns, :parts, Names.split_emoji(assigns.account.name))

    ~H"""
    <span :if={elem(@parts, 0)}>{elem(@parts, 0)}</span>
    <span class={elem(@parts, 0) && "app-wide"}>{elem(@parts, 1)}</span>
    """
  end

  attr :transaction, :map, required: true
  attr :accounts, :map, required: true

  defp category(assigns) do
    ~H"""
    <span :if={@transaction.subtransactions != []} class="text-base-content/70">
      {category_text(@transaction, @accounts)}
    </span>
    <span :if={uncategorised?(@transaction, @accounts)} class="app-uncategorised">
      Nicht kategorisiert
    </span>
    <span :if={@transaction.subtransactions == [] and !uncategorised?(@transaction, @accounts)}>
      {category_text(@transaction, @accounts)}
    </span>
    """
  end

  attr :amount, :integer, required: true

  defp signed(assigns) do
    ~H"""
    <.amount value={@amount} signed class={["font-semibold", @amount > 0 && "text-success-ink"]} />
    """
  end

  defp uncategorised?(transaction, accounts),
    do: is_nil(transaction.category) and Rows.categorisable?(transaction, accounts)

  defp category_text(%{subtransactions: [_ | _] = parts}, _accounts),
    do: "Aufgeteilt (#{length(parts)})"

  defp category_text(%{category: %{internal: true}}, _accounts), do: "Einnahme: Zu verteilen"

  defp category_text(%{category: %{name: name, category_group: group}}, _accounts),
    do: CategoryOptions.text(group.name, name)

  # A subtransaction's: a transfer to another budget account has none.
  defp category_text(%Subtransaction{payee: %Payee{transfer_account_id: id}}, _accounts)
       when not is_nil(id),
       do: ""

  defp category_text(%Subtransaction{}, _accounts), do: "Nicht kategorisiert"

  defp category_text(transaction, accounts),
    do: if(uncategorised?(transaction, accounts), do: "Nicht kategorisiert", else: "")

  defp payee(%{payee: %Payee{transfer_account_id: id}}, accounts) when not is_nil(id),
    do: "↔ " <> accounts[id].name

  defp payee(%{payee: %Payee{name: name}}, _accounts), do: name
  defp payee(_transaction, _accounts), do: ""

  defp outflow(amount) when amount < 0, do: Money.amount(-amount)
  defp outflow(_amount), do: ""

  defp inflow(amount) when amount > 0, do: Money.amount(amount)
  defp inflow(_amount), do: ""

  defp reconciled(transactions), do: Enum.filter(transactions, &(&1.cleared == :reconciled))

  # Reconciled themselves or through a counterpart, as deleting goes for both sides.
  defp locked(transactions) do
    Enum.filter(transactions, fn transaction ->
      [transaction | transaction.subtransactions]
      |> Enum.flat_map(&[&1, &1.transfer_transaction])
      |> Enum.any?(&match?(%Transaction{cleared: :reconciled, deleted_at: nil}, &1))
    end)
  end

  defp delete_question(transactions) do
    case {length(transactions), length(locked(transactions))} do
      {1, 0} -> "Buchung löschen?"
      {1, 1} -> "Diese Buchung ist abgeglichen. Trotzdem löschen?"
      {count, 0} -> "#{count} Buchungen löschen?"
      {count, 1} -> "#{count} Buchungen löschen? Eine davon ist abgeglichen."
      {count, locked} -> "#{count} Buchungen löschen? #{locked} davon sind abgeglichen."
    end
  end

  # Merging changes the matched transaction's date, also on reconciled counterparts.
  defp merge_question(proposals) do
    case proposals |> Enum.map(& &1.matched_transaction) |> locked() |> length() do
      0 -> nil
      1 -> "Eine Gegenbuchung ist abgeglichen. Trotzdem zuordnen?"
      count -> "#{count} Gegenbuchungen sind abgeglichen. Trotzdem zuordnen?"
    end
  end

  defp confirm(transactions, value \\ ["phx-value-reconciled": "confirmed"]),
    do: asking(question(transactions), "Ändern", "Der gebuchte Saldo bleibt gleich.", value)

  defp confirm_merge(proposals),
    do: asking(merge_question(proposals), "Zuordnen", merge_text())

  defp merge_text, do: "Das Datum aus dem Import gilt dann auf beiden Seiten der Umbuchung."

  # A `<.button>` that asks before changing reconciled transactions and tells the server it did.
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :class, :any, default: nil

  defp empty(%{hint: nil} = assigns), do: ~H"<.empty_state title={@title} class={@class} />"

  defp empty(assigns) do
    ~H"""
    <.empty_state title={@title} class={@class}>{@hint}</.empty_state>
    """
  end

  defp asking(question, label, text, value \\ ["phx-value-reconciled": "confirmed"])
  defp asking(nil, _label, _text, _value), do: []

  defp asking(question, label, text, value),
    do: [confirm: question, confirm_label: label, confirm_text: text] ++ value

  defp question([%{cleared: :reconciled}]),
    do: "Diese Buchung ist abgeglichen. Trotzdem ändern?"

  defp question(transactions) do
    case length(reconciled(transactions)) do
      0 -> nil
      1 -> "Eine abgeglichene Buchung ist dabei. Trotzdem ändern?"
      count -> "#{count} abgeglichene Buchungen sind dabei. Trotzdem ändern?"
    end
  end
end

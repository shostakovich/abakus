defmodule AbakusWeb.RegisterLive.Components do
  @moduledoc """
  The parts of the register: banner, account line, balances, toolbar, selection bar, the table on desktops and the
  compact cards on phones. A click into a selected row (on phones a card) opens the transaction editor. Actions
  that change a reconciled transaction carry a `data-confirm` question and send `reconciled: "confirmed"`.
  """
  use AbakusWeb, :html

  alias Abakus.Ledger.{Account, Payee, Subtransaction, Transaction}
  alias Abakus.Names
  alias AbakusWeb.{AccountGroups, CategoryOptions, Format}
  alias AbakusWeb.RegisterLive.{Rows, TransactionEditor}
  alias Phoenix.LiveView.JS

  @flags [
    red: "Rot",
    orange: "Orange",
    yellow: "Gelb",
    green: "Grün",
    blue: "Blau",
    purple: "Lila"
  ]

  @feeds %{
    portfolio: "Wert kommt aus der Depot-App",
    shared_expenses: "Buchungen kommen aus der Ausgaben-App"
  }

  attr :transactions, :list, required: true

  attr :show_path, :any,
    required: true,
    doc: "where \"Ansehen\" leads, false in that view already"

  def banner(assigns) do
    assigns = assign(assigns, :count, length(assigns.transactions))

    ~H"""
    <div
      id="unapproved-banner"
      class="alert alert-primary d-flex align-items-center gap-2 py-1 py-md-2 mb-3 app-banner"
    >
      <.icon name="info" />
      <span class="me-auto text-truncate">
        <span class="d-md-none">{@count} neu</span>
        <span class="d-none d-md-inline">
          {if @count == 1, do: "1 neue Buchung", else: "#{@count} neue Buchungen"} zu bestätigen oder zu kategorisieren
        </span>
      </span>
      <.link :if={@show_path} id="show-unapproved" patch={@show_path} class="btn btn-sm btn-primary">
        Ansehen
      </.link>
      <button
        id="approve-all"
        type="button"
        class="btn btn-sm btn-outline-primary"
        phx-click="approve_all"
        {confirm(@transactions)}
      >
        <span class="d-md-none">Alle</span><span class="d-none d-md-inline">Alle bestätigen</span>
      </button>
    </div>
    """
  end

  attr :account, Account, default: nil

  def meta(assigns) do
    ~H"""
    <div
      id="register-meta"
      class="small text-body-secondary d-flex flex-wrap column-gap-3 mt-1 mb-2 app-reg-meta"
    >
      <%= if @account do %>
        <span>{AccountGroups.kind_label(@account.kind)}</span>
        <span :if={@account.closed}>Geschlossen</span>
        <span :if={@account.last_reconciled_at} class="d-inline-flex align-items-center gap-1">
          <.icon name="lock" class="app-icon-sm" />
          Abgeglichen am {Format.date(DateTime.to_date(@account.last_reconciled_at))}
        </span>
        <span :if={@account.note}>{@account.note}</span>
      <% else %>
        <span>Budget- und Tracking-Konten</span>
      <% end %>
    </div>
    """
  end

  attr :account, Account, default: nil
  attr :balances, :map, required: true

  @doc """
  One account: the balance equation, or for a depot only its value. All accounts: the budget accounts' equation,
  tracking and the total. Phones get one line that opens the rest.
  """
  def balances(assigns) do
    ~H"""
    <div class="d-none d-md-flex flex-wrap align-items-center gap-3 mb-3">
      <%= cond do %>
        <% portfolio?(@account) -> %>
          <.figure id="balance-working" value={@balances.working} label="Wert laut Depot-App" />
        <% @account -> %>
          <.equation balances={@balances} ids />
        <% true -> %>
          <div>
            <div class="small fw-semibold text-uppercase text-body-secondary mb-1">Budgetkonten</div>
            <.equation balances={@balances.budget} ids />
          </div>
          <div class="vr"></div>
          <.figure id="balance-tracking" value={@balances.tracking} label="Tracking" />
          <div class="vr"></div>
          <.figure id="balance-total" value={@balances.total} label="Gesamt" tone />
      <% end %>
    </div>
    <details class="d-md-none mb-2 app-bal-compact">
      <summary class="d-flex align-items-center gap-2">
        <span class={["fw-semibold app-q", headline(@account, @balances) < 0 && "app-neg"]}>
          {Format.euros(headline(@account, @balances))}
        </span>
        <span class="text-body-secondary small">{headline_label(@account)}</span>
        <.icon name="chevron" class="app-icon-sm text-body-secondary app-sum-chev" />
      </summary>
      <div :if={!portfolio?(@account)} class="pt-2">
        <.equation balances={if @account, do: @balances, else: @balances.budget} />
        <div :if={!@account} class="d-flex gap-3 mt-2">
          <.figure value={@balances.tracking} label="Tracking" />
        </div>
      </div>
    </details>
    """
  end

  defp portfolio?(account), do: match?(%Account{fed_by: :portfolio}, account)

  defp headline(nil, balances), do: balances.total
  defp headline(_account, balances), do: balances.working

  defp headline_label(nil), do: "Gesamt"
  defp headline_label(%Account{fed_by: :portfolio}), do: "Wert"
  defp headline_label(_account), do: "Arbeitssaldo"

  attr :balances, :map, required: true
  attr :ids, :boolean, default: false

  defp equation(assigns) do
    ~H"""
    <div class="d-flex flex-column flex-sm-row flex-wrap gap-1 gap-sm-3">
      <.figure
        id={@ids && "balance-cleared"}
        value={@balances.cleared}
        label="Abgeglichen"
        tone
      />
      <.figure
        id={@ids && "balance-uncleared"}
        op="+"
        value={@balances.uncleared}
        label="Nicht abgeglichen"
      />
      <.figure
        id={@ids && "balance-working"}
        op="="
        value={@balances.working}
        label="Arbeitssaldo"
        tone
      />
    </div>
    """
  end

  attr :id, :any, default: nil
  attr :op, :string, default: nil
  attr :value, :integer, required: true
  attr :label, :string, required: true
  attr :tone, :boolean, default: false, doc: "green when positive, as the totals are"

  defp figure(assigns) do
    ~H"""
    <div class="d-flex align-items-baseline gap-2">
      <span :if={@op} class="fs-5 text-body-secondary" aria-hidden="true">{@op}</span>
      <div>
        <div
          id={@id}
          class={[
            "fs-5 fw-semibold app-q text-nowrap",
            @value < 0 && "app-neg",
            @tone && @value >= 0 && "text-success"
          ]}
        >
          {Format.euros(@value)}
        </div>
        <div class="small text-body-secondary">{@label}</div>
      </div>
    </div>
    """
  end

  attr :account, Account, default: nil

  attr :manual, :boolean, required: true, doc: "whether \"Buchung\" adds a transaction here"

  attr :filter, :atom, required: true
  attr :query, :string, required: true
  attr :running, :boolean, required: true
  attr :running_shown, :boolean, required: true
  attr :paths, :map, required: true

  def toolbar(assigns) do
    ~H"""
    <div class="d-flex align-items-center gap-1 border-top border-bottom py-2 mb-2 app-reg-tools">
      <button
        :if={@manual}
        id="new-transaction"
        type="button"
        class="btn btn-sm btn-link text-decoration-none d-none d-md-inline-flex align-items-center gap-1"
        phx-click="new"
        phx-value-layout="row"
      >
        <.icon name="plus" class="app-icon-sm" /> Buchung
      </button>
      <.link
        :if={@manual}
        id="file-import"
        navigate={~p"/import"}
        class="btn btn-sm btn-link text-decoration-none d-inline-flex align-items-center gap-1"
      >
        <.icon name="file" class="app-icon-sm" />
        <span class="d-md-none">Import</span><span class="d-none d-md-inline">Datei-Import</span>
      </.link>
      <span
        :if={@account && @account.fed_by}
        id="feed-hint"
        class="small text-body-secondary d-inline-flex align-items-center gap-1 px-2"
      >
        <.icon name="info" class="app-icon-sm" />
        {feed_hint(@account)}, keine Buchungen von Hand oder per Datei
      </span>
      <span
        :if={@account && @running && !@running_shown}
        id="running-hint"
        class="small text-body-secondary px-2"
      >
        Laufender Saldo nur in „Alle Buchungen“ ohne Suche
      </span>
      <div class="dropdown ms-auto" phx-click-away={hide_dropdown("#view-menu", "#view-toggle")}>
        <button
          id="view-toggle"
          type="button"
          class="btn btn-sm btn-link text-decoration-none dropdown-toggle"
          aria-expanded="false"
          aria-controls="view-menu"
          phx-click={toggle_dropdown("#view-menu", "#view-toggle")}
        >
          {view_label(@filter)}
        </button>
        <ul id="view-menu" class="dropdown-menu dropdown-menu-end" data-bs-popper="static">
          <li :for={{filter, label} <- filter_labels()}>
            <.link
              class={["dropdown-item", @filter == filter && "active"]}
              aria-current={@filter == filter && "true"}
              patch={@paths.filters[filter]}
            >
              {label}
            </.link>
          </li>
          <li :if={@account}><hr class="dropdown-divider" /></li>
          <li :if={@account}>
            <.link
              id="running-toggle"
              class="dropdown-item d-flex align-items-center gap-2"
              patch={@paths.running}
              aria-pressed={to_string(@running)}
            >
              <.icon name="check" class={["app-icon-sm", !@running && "invisible"]} /> Laufender Saldo
            </.link>
          </li>
        </ul>
      </div>
      <form
        id="register-search"
        class="input-group input-group-sm app-reg-search"
        role="search"
        phx-change="search"
        phx-submit="search"
      >
        <span class="input-group-text"><.icon name="search" class="app-icon-sm" /></span>
        <input
          type="search"
          name="q"
          value={@query}
          class="form-control"
          placeholder="Suchen"
          aria-label="Buchungen durchsuchen"
          phx-debounce="300"
        />
      </form>
    </div>
    """
  end

  defp feed_hint(account), do: @feeds[account.fed_by]

  defp filter_labels,
    do: [all: "Alle Buchungen", unapproved: "Zu bestätigen", uncleared: "Nicht abgeglichen"]

  defp view_label(:all), do: "Ansicht"
  defp view_label(:unapproved), do: "Ansicht: zu bestätigen"
  defp view_label(:uncleared), do: "Ansicht: nicht abgeglichen"

  attr :selected, :list, required: true
  attr :categories, :list, required: true

  @doc """
  The selection bar as in YNAB, floating at the bottom: how many are selected (× clears), approve when one of them
  waits, categorise with the category picker, and under "Mehr" delete.
  """
  def bulk(assigns) do
    assigns =
      assign(assigns,
        count: length(assigns.selected),
        waiting: Enum.reject(assigns.selected, & &1.approved)
      )

    ~H"""
    <div
      id="bulk"
      class="d-none d-md-flex align-items-center gap-1 app-bulk"
      role="toolbar"
      aria-label="Ausgewählte Buchungen"
    >
      <button
        id="clear-selection"
        type="button"
        class="btn btn-sm app-bulk-btn"
        aria-label="Auswahl aufheben"
        title="Auswahl aufheben"
        phx-click="clear_selection"
      >
        ×
      </button>
      <span class="px-1 fw-semibold text-nowrap">
        {if @count == 1, do: "1 Buchung", else: "#{@count} Buchungen"}
      </span>
      <span class="app-bulk-sep"></span>
      <button
        :if={@waiting != []}
        id="approve-selected"
        type="button"
        class="btn btn-sm app-bulk-btn"
        phx-click="approve_selected"
        {confirm(@waiting)}
      >
        <.icon name="check" class="app-icon-sm" /> Bestätigen
      </button>
      <div class="dropup" phx-click-away={hide_dropdown("#categorise-menu", "#categorise-toggle")}>
        <button
          id="categorise-toggle"
          type="button"
          class="btn btn-sm app-bulk-btn"
          aria-expanded="false"
          aria-controls="categorise-menu"
          phx-click={
            toggle_dropdown("#categorise-menu", "#categorise-toggle")
            |> JS.focus(to: "#categorise-input")
          }
        >
          Kategorisieren
        </button>
        <div id="categorise-menu" class="dropdown-menu p-2 app-bulk-menu" data-bs-popper="static">
          <form
            id="categorise-form"
            phx-submit={
              JS.push("categorise_selected")
              |> hide_dropdown("#categorise-menu", "#categorise-toggle")
            }
          >
            <input
              :if={reconciled(@selected) != []}
              type="hidden"
              name="reconciled"
              value="confirmed"
            />
            <div
              id="categorise-combo"
              class="app-combo app-combo-up"
              phx-hook="Combobox"
              data-options="categorise-options"
              data-field="category"
              data-submit="categorise-submit"
            >
              <input
                id="categorise-input"
                type="text"
                class="form-control form-control-sm"
                role="combobox"
                aria-label="Kategorie"
                aria-autocomplete="list"
                aria-controls="categorise-list"
                placeholder="Kategorie suchen"
                autocomplete="off"
              />
              <input type="hidden" name="category_id" value="" />
              <div id="categorise-list" class="app-combo-menu" role="listbox" phx-update="ignore">
              </div>
            </div>
            <button
              id="categorise-submit"
              type="submit"
              class="d-none"
              data-confirm={question(@selected)}
            >
              Kategorisieren
            </button>
          </form>
          <.category_template id="categorise-options" categories={@categories} />
        </div>
      </div>
      <div class="dropup" phx-click-away={hide_dropdown("#bulk-more", "#bulk-more-toggle")}>
        <button
          id="bulk-more-toggle"
          type="button"
          class="btn btn-sm app-bulk-btn"
          aria-expanded="false"
          aria-controls="bulk-more"
          phx-click={toggle_dropdown("#bulk-more", "#bulk-more-toggle")}
        >
          ⋯ Mehr
        </button>
        <ul id="bulk-more" class="dropdown-menu dropdown-menu-end" data-bs-popper="static">
          <li>
            <button
              id="delete-selected"
              type="button"
              class="dropdown-item text-danger"
              phx-click="delete_selected"
              phx-value-reconciled={locked(@selected) != [] && "confirmed"}
              data-confirm={delete_question(@selected)}
            >
              Löschen
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :categories, :list, required: true
  slot :inner_block, doc: "below the options"

  @doc "The category picker's options (see the `Combobox` hook): by group, each with what it has available."
  def category_template(assigns) do
    ~H"""
    <template id={@id}>
      <div :for={group <- @categories} class="app-combo-group" role="group" aria-label={group.name}>
        <div class="app-combo-head">{group.name}</div>
        <div
          :for={option <- group.options}
          class="app-combo-opt d-flex gap-2"
          role="option"
          data-value={option.id}
          data-key={option.key}
          data-label={option.text}
        >
          <span class="text-truncate me-auto">{option.name}</span>
          <span class={["app-q", available_class(option.available)]}>
            {Format.amount(option.available)}
          </span>
        </div>
      </div>
      {render_slot(@inner_block)}
    </template>
    """
  end

  defp available_class(amount) when amount > 0, do: "text-success"
  defp available_class(amount) when amount < 0, do: "app-neg"
  defp available_class(_zero), do: "text-body-secondary"

  attr :rows, :list, required: true
  attr :accounts, :map, required: true
  attr :columns, :map, required: true, doc: "`%{all, category, running, count}`, see `columns/2`"
  attr :selected, :any, required: true
  attr :flag_menu, :any, required: true
  attr :running, :map, default: nil

  attr :editor, :any,
    required: true,
    doc: "the transaction editor's assigns while a row is edited"

  attr :empty, :string, required: true

  @doc """
  The register on desktops, as in YNAB: a click selects a row, a click into a cell of a selected row opens it for
  editing there, with the cursor in that cell. Each transaction is a `<tbody>` of its own, so a split keeps its
  subtransactions below it, collapsible, and the editor (`TransactionEditor`) takes its place while it is edited.
  """
  def table(assigns) do
    assigns =
      assign(assigns,
        all_selected:
          assigns.rows != [] and MapSet.size(assigns.selected) == length(assigns.rows),
        edited: assigns.editor && assigns.editor.row_id
      )

    ~H"""
    <div class="d-none d-md-block">
      <table
        id="register-table"
        class={[
          "table table-sm table-hover align-middle app-reg mb-0",
          @columns.all && "app-reg-all",
          @editor && "app-reg-editing"
        ]}
      >
        <thead>
          <tr>
            <th class="app-pick">
              <input
                id="select-all"
                type="checkbox"
                class="form-check-input"
                checked={@all_selected}
                phx-click="select_all"
                aria-label="Alle auswählen"
              />
            </th>
            <th class="app-flag-col">
              <span class="visually-hidden">Markierung</span><.icon name="flag" class="app-icon-sm" />
            </th>
            <th class="app-date-col">Datum</th>
            <th :if={@columns.all}>Konto</th>
            <th class="app-payee">Empfänger</th>
            <th :if={@columns.category}>Kategorie</th>
            <th class="app-memo-col">Memo</th>
            <th class="text-end app-amount-col">Ausgang</th>
            <th class="text-end app-amount-col">Eingang</th>
            <th :if={@columns.running} class="text-end">Saldo</th>
            <th class="text-center app-c-col">
              <span class="visually-hidden">Abgeglichen, bestätigen</span>C
            </th>
          </tr>
        </thead>
        <.live_component :if={@edited == :new} module={TransactionEditor} {@editor.assigns} />
        <%= for transaction <- @rows do %>
          <%= if @edited == transaction.id do %>
            <.live_component module={TransactionEditor} {@editor.assigns} />
          <% else %>
            <.row
              transaction={transaction}
              accounts={@accounts}
              columns={@columns}
              selected={transaction.id in @selected}
              flag_open={@flag_menu == transaction.id}
              running={@running}
            />
          <% end %>
        <% end %>
        <tbody :if={@rows == []}>
          <tr>
            <td colspan={@columns.count} class="text-center text-body-secondary py-4">{@empty}</td>
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
  attr :flag_open, :boolean, required: true
  attr :running, :map, default: nil

  defp row(assigns) do
    ~H"""
    <tbody
      id={"tx-#{@transaction.id}-rows"}
      class={["app-tx", @selected && "is-selected"]}
    >
      <tr
        id={"tx-#{@transaction.id}"}
        class={[
          "app-tx-main",
          !@transaction.approved && "app-unapproved",
          @selected && "table-active"
        ]}
      >
        <td class="app-pick">
          <input
            id={"tx-#{@transaction.id}-select"}
            type="checkbox"
            class="form-check-input"
            checked={@selected}
            phx-click="select"
            phx-value-id={@transaction.id}
            aria-label="Buchung auswählen"
          />
        </td>
        <td>
          <.flag transaction={@transaction} open={@flag_open} />
        </td>
        <td {cell(@transaction, "date")}>
          <span class="app-wide">{Format.date(@transaction.date)}</span>
          <span class="app-short">{Format.day(@transaction.date)}</span>
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
          <div class="text-truncate app-payee-name">
            {payee(@transaction, @accounts)}<span
              :if={payee(@transaction, @accounts) == ""}
              class="text-body-secondary"
            >Ohne Empfänger</span>
          </div>
          <div :if={@transaction.memo} class="small text-body-secondary text-truncate app-short">
            {@transaction.memo}
          </div>
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
            <.icon name="down" class="app-icon-sm" />
          </button>
          <.category transaction={@transaction} accounts={@accounts} />
        </td>
        <td class="small text-body-secondary text-truncate app-memo-col" {cell(@transaction, "memo")}>
          {@transaction.memo}
        </td>
        <td class="text-end app-q app-out" {cell(@transaction, "outflow")}>
          {outflow(@transaction.amount)}
        </td>
        <td class="text-end app-q app-in" {cell(@transaction, "inflow")}>
          {inflow(@transaction.amount)}
        </td>
        <td :if={@running} class="text-end app-q text-body-secondary app-run">
          {Format.amount(@running[@transaction.id])}
        </td>
        <td class="text-end text-nowrap app-c-col">
          <.approve
            :if={!@transaction.approved}
            id={"tx-#{@transaction.id}-approve"}
            transaction={@transaction}
            accounts={@accounts}
            class="btn btn-sm btn-primary app-approve"
          />
          <.cleared id={"tx-#{@transaction.id}-cleared"} transaction={@transaction} />
        </td>
      </tr>
      <tr
        :for={{part, index} <- Enum.with_index(@transaction.subtransactions)}
        id={"tx-#{@transaction.id}-part-#{index}"}
        class={["app-part", @selected && "table-active"]}
      >
        <td></td>
        <td></td>
        <td {cell(@transaction, "date")}></td>
        <td :if={@columns.all} {cell(@transaction, "account")}></td>
        <td class="app-payee text-truncate" {cell(@transaction, "payee")}>
          {payee(part, @accounts)}
        </td>
        <td :if={@columns.category} class="app-catcol" {cell(@transaction, "category")}>
          {category_text(part, @accounts)}
        </td>
        <td class="small text-body-secondary text-truncate app-memo-col" {cell(@transaction, "memo")}>
          {part.memo}
        </td>
        <td class="text-end app-q app-out" {cell(@transaction, "outflow")}>{outflow(part.amount)}</td>
        <td class="text-end app-q app-in" {cell(@transaction, "inflow")}>{inflow(part.amount)}</td>
        <td :if={@running}></td>
        <td></td>
      </tr>
    </tbody>
    """
  end

  # A cell that selects its row, or opens the selected row for editing in that cell.
  defp cell(transaction, field),
    do: ["phx-click": "row_click", "phx-value-id": transaction.id, "phx-value-field": field]

  attr :rows, :list, required: true
  attr :accounts, :map, required: true
  attr :all, :boolean, required: true
  attr :empty, :string, required: true

  @doc """
  Phones: one compact card per transaction, which opens the transaction sheet; one waiting for approval puts its ✓
  at the side.
  """
  def cards(assigns) do
    ~H"""
    <div id="register-cards" class="list-group d-md-none">
      <%= for transaction <- @rows do %>
        <div
          :if={!transaction.approved}
          id={"tx-card-#{transaction.id}"}
          class="list-group-item app-unapproved-item d-flex align-items-center gap-2"
        >
          <.link
            id={"tx-card-#{transaction.id}-edit"}
            phx-click="edit"
            phx-value-id={transaction.id}
            class="d-block flex-grow-1 app-min-w-0 text-reset text-decoration-none"
          >
            <div class="d-flex align-items-start gap-2">
              <span class="app-payee-ph flex-grow-1 app-min-w-0">{payee(transaction, @accounts)}</span>
              <.signed amount={transaction.amount} class="fw-bold" />
            </div>
            <div class="d-flex align-items-center gap-2 app-ph-l2 small">
              <span class="text-body-secondary flex-shrink-0">
                {Format.day(transaction.date)}<span :if={@all}> · {@accounts[transaction.account_id].name}</span>
              </span>
              <span class="text-truncate"><.category transaction={transaction} accounts={@accounts} /></span>
            </div>
          </.link>
          <.approve
            id={"tx-card-#{transaction.id}-approve"}
            transaction={transaction}
            accounts={@accounts}
            class="btn btn-primary app-approve-ph"
          />
        </div>
        <div
          :if={transaction.approved}
          id={"tx-card-#{transaction.id}"}
          class="list-group-item d-flex gap-2 align-items-start"
        >
          <span class="pt-1">
            <.cleared id={"tx-card-#{transaction.id}-cleared"} transaction={transaction} />
          </span>
          <.link
            id={"tx-card-#{transaction.id}-edit"}
            phx-click="edit"
            phx-value-id={transaction.id}
            class="d-block flex-grow-1 app-min-w-0 text-reset text-decoration-none"
          >
            <div class="app-payee-ph">{payee(transaction, @accounts)}</div>
            <div class="small text-body-secondary text-truncate">
              {Format.day(transaction.date)}<span :if={@all}> · {@accounts[transaction.account_id].name}</span>
              <span :if={category_text(transaction, @accounts) != ""}>
                · <.category transaction={transaction} accounts={@accounts} />
              </span>
            </div>
            <div :if={transaction.memo} class="small text-body-secondary text-truncate">
              {transaction.memo}
            </div>
          </.link>
          <span
            :if={transaction.flag}
            class={["app-flag is-set", "app-flag-#{transaction.flag}"]}
            title={"Markierung: #{flag_label(transaction.flag)}"}
          >
            <.icon name="flag" class="app-icon-sm" />
          </span>
          <.signed amount={transaction.amount} class="fw-semibold" />
        </div>
      <% end %>
      <div :if={@rows == []} class="list-group-item text-center text-body-secondary py-4">
        {@empty}
      </div>
    </div>
    """
  end

  def legend(assigns) do
    ~H"""
    <div class="small text-body-secondary mt-2 d-flex flex-wrap gap-3">
      <span class="d-inline-flex align-items-center gap-1">
        <span class="app-clear">C</span> nicht abgeglichen
      </span>
      <span class="d-inline-flex align-items-center gap-1">
        <span class="app-clear is-cleared">C</span> abgeglichen (bei der Bank gebucht)
      </span>
      <span class="d-inline-flex align-items-center gap-1">
        <span class="app-clear is-reconciled"><.icon name="lock" class="app-icon-sm" /></span>
        abgeschlossen, gesperrt
      </span>
    </div>
    """
  end

  attr :transaction, :map, required: true
  attr :open, :boolean, required: true

  defp flag(assigns) do
    assigns = assign(assigns, :flags, @flags)

    ~H"""
    <div class="dropdown" phx-click-away={@open && "close_flag_menu"}>
      <button
        id={"tx-#{@transaction.id}-flag"}
        type="button"
        class={["app-flag", @transaction.flag && "is-set app-flag-#{@transaction.flag}"]}
        aria-label={"Markierung: #{flag_label(@transaction.flag)}, ändern"}
        aria-expanded={to_string(@open)}
        title="Markierung"
        phx-click="flag_menu"
        phx-value-id={@transaction.id}
      >
        <.icon name="flag" class="app-icon-sm" />
      </button>
      <div
        :if={@open}
        id="flag-menu"
        class="dropdown-menu show p-2 app-flag-menu"
        data-bs-popper="static"
        phx-window-keydown="close_flag_menu"
        phx-key="Escape"
      >
        <div class="fw-semibold small mb-2">Markierung</div>
        <div class="d-flex flex-wrap gap-1">
          <button
            :for={{flag, label} <- @flags}
            id={"flag-menu-#{flag}"}
            type="button"
            class={[
              "btn btn-sm btn-light d-inline-flex align-items-center gap-1",
              @transaction.flag == flag && "active"
            ]}
            phx-click="set_flag"
            phx-value-id={@transaction.id}
            phx-value-flag={flag}
            {confirm([@transaction])}
          >
            <.icon name="flag" class={"app-icon-sm app-flag-#{flag}"} />{label}
          </button>
          <button
            id="flag-menu-none"
            type="button"
            class={["btn btn-sm btn-light", is_nil(@transaction.flag) && "active"]}
            phx-click="set_flag"
            phx-value-id={@transaction.id}
            phx-value-flag=""
            {confirm([@transaction])}
          >
            keine
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp flag_label(nil), do: "keine"
  defp flag_label(flag), do: @flags[flag]

  attr :id, :string, required: true
  attr :transaction, :map, required: true

  defp cleared(%{transaction: %{cleared: :reconciled}} = assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="app-clear is-reconciled"
      title="Abgeschlossen"
      aria-label="Abgeschlossen, entsperren"
      phx-click="toggle_cleared"
      phx-value-id={@transaction.id}
      phx-value-reconciled="confirmed"
      data-confirm="Diese Buchung ist abgeschlossen. Entsperren?"
    >
      <.icon name="lock" class="app-icon-sm" />
    </button>
    """
  end

  defp cleared(assigns) do
    assigns = assign(assigns, :cleared?, assigns.transaction.cleared == :cleared)

    ~H"""
    <button
      id={@id}
      type="button"
      class={["app-clear", @cleared? && "is-cleared"]}
      aria-label={if @cleared?, do: "Abgeglichen, umschalten", else: "Nicht abgeglichen, umschalten"}
      phx-click="toggle_cleared"
      phx-value-id={@transaction.id}
    >
      C
    </button>
    """
  end

  attr :id, :string, required: true
  attr :transaction, :map, required: true
  attr :accounts, :map, required: true
  attr :class, :string, required: true

  defp approve(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class={@class}
      title="Bestätigen"
      aria-label={"#{payee(@transaction, @accounts)} bestätigen"}
      phx-click="approve"
      phx-value-id={@transaction.id}
      {confirm([@transaction])}
    >
      <.icon name="check" class="app-icon-sm" />
    </button>
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
    <span :if={@transaction.subtransactions != []} class="text-body-secondary">
      {category_text(@transaction, @accounts)}
    </span>
    <span :if={uncategorised?(@transaction, @accounts)} class="text-warning-emphasis">
      Nicht kategorisiert
    </span>
    <span :if={@transaction.subtransactions == [] and !uncategorised?(@transaction, @accounts)}>
      {category_text(@transaction, @accounts)}
    </span>
    """
  end

  attr :amount, :integer, required: true
  attr :class, :string, default: nil

  defp signed(assigns) do
    ~H"""
    <span class={["app-q text-nowrap", @class, @amount > 0 && "text-success"]}>
      {Format.signed_euros(@amount)}
    </span>
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

  defp outflow(amount) when amount < 0, do: Format.amount(-amount)
  defp outflow(_amount), do: ""

  defp inflow(amount) when amount > 0, do: Format.amount(amount)
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
      {1, 1} -> "Diese Buchung ist abgeschlossen. Trotzdem löschen?"
      {count, 0} -> "#{count} Buchungen löschen?"
      {count, 1} -> "#{count} Buchungen löschen? Eine davon ist abgeschlossen."
      {count, locked} -> "#{count} Buchungen löschen? #{locked} davon sind abgeschlossen."
    end
  end

  # Attributes that make the browser ask before changing reconciled transactions, and tell the server it did.
  defp confirm(transactions) do
    case question(transactions) do
      nil -> []
      question -> ["data-confirm": question, "phx-value-reconciled": "confirmed"]
    end
  end

  defp question([%{cleared: :reconciled}]),
    do: "Diese Buchung ist abgeschlossen. Trotzdem ändern?"

  defp question(transactions) do
    case length(reconciled(transactions)) do
      0 -> nil
      1 -> "Eine abgeschlossene Buchung ist dabei. Trotzdem ändern?"
      count -> "#{count} abgeschlossene Buchungen sind dabei. Trotzdem ändern?"
    end
  end
end

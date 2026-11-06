defmodule AbakusWeb.RegisterLive.TransactionEditor do
  @moduledoc """
  Edits a transaction as YNAB does, for a new one and an existing one alike. On desktops (`layout: :row`) it replaces
  the transaction's rows in the register on one line: inputs in every column, Cancel and Save (Approve for one waiting
  for approval) where approve and status stand, Enter saves and Escape cancels; a split's subtransactions as rows below,
  each with a payee field only where it differs from the transaction's. Each side has one amount field behind a sign
  button; a click or a sign typed in front sets the side's direction, a new transaction's is an outflow. Amounts may add
  and subtract ("50+20"); one that reads as none is refused at its field as it is left and on saving, as the budget's
  Zugewiesen does, keeping the text and the focus. Its root is a `<tbody>`, the inputs outside the first row belong to `#tx-form` by their `form`
  attribute. Phones (`layout: :sheet`) get a sheet from the bottom with the amount first. The form's state is
  `AbakusWeb.TransactionForm` params.

  Payee, category and a split's parts are the fields it shares with the scheduled transaction's dialog (`EditorFields`,
  `EditorState`); the portfolios' cash accounts (`depot_cash`) are offered only where the transaction uses one already.
  Changing or deleting a reconciled transaction, or one whose counterpart is, asks first. A transaction its source leads
  (`Ledger.led_by/2`, ADR 0020) links to its Kasse expense or Depot transaction and keeps what the source leads
  (`Ledger.led_fields/0`); it is neither split nor deleted here. A transfer with the shared-expenses account becomes a
  reimbursement in the Kasse (`Abakus.Kasse.BudgetLink.write_from_register/4`), which asks for the person while the
  group has more than one besides the budget owner.

  Tells its LiveView `{TransactionEditor, :done, message}` once the transaction is saved or deleted; the events
  `cancel_edit` (Cancel, Escape) go to the LiveView itself.
  """
  use AbakusWeb, :live_component

  alias Abakus.Kasse.BudgetLink
  alias Abakus.{Ledger, Money}
  alias Abakus.Ledger.Transaction
  alias AbakusWeb.BudgetLive.Components, as: BudgetComponents
  alias AbakusWeb.RegisterLive.{EditorFields, EditorState}
  alias AbakusWeb.TransactionForm

  import EditorFields,
    only: [
      add_button: 1,
      amount_errors: 1,
      amount_field: 1,
      category_cell: 1,
      change_payee: 1,
      describedby: 3,
      option_lists: 1,
      own_payee?: 3,
      parts: 1,
      payee_combo: 1,
      remove_button: 1,
      side_name: 1,
      sign_label: 1,
      sub_name: 2,
      typed: 1
    ]

  @main "main"

  @linked_delete "Eine Buchung aus der Kasse wird mit ihrer Ausgabe gelöscht."

  @depot_delete "Diese Buchung bucht das Depot; sie lässt sich hier nicht löschen."

  @doc "Why a transaction linked to a Kasse expense cannot be deleted in the register."
  def linked_delete, do: @linked_delete

  @doc "Why a transaction the Depot booked cannot be deleted in the register."
  def depot_delete, do: @depot_delete

  @labels %{
    account_id: "Konto",
    date: "Datum",
    amount: "Betrag",
    payee_id: "Empfänger",
    category_id: "Kategorie",
    counterpart_category_id: "Kategorie",
    memo: "Memo",
    cleared: "Buchung",
    name: "Empfänger",
    transfer_transaction_id: "Gegenbuchung",
    transfer_subtransaction_id: "Buchung",
    matched_transaction_id: "Zugeordnete Buchung"
  }

  @impl true
  def render(%{layout: :sheet} = assigns) do
    assigns = EditorFields.assign_options(assigns)

    ~H"""
    <div id={@id}>
      <.modal
        id="tx-sheet"
        show
        title={if @transaction, do: "Buchung bearbeiten", else: "Neue Buchung"}
        on_cancel={JS.push("cancel_edit")}
        class="app-sheet"
      >
        <.form
          for={%{}}
          id="tx-form"
          class="flex flex-col gap-1 pt-2"
          phx-change="change"
          phx-submit="save"
          phx-target={@myself}
          phx-mounted={is_nil(@transaction) && JS.focus(to: "#tx-amount")}
          phx-hook="AmountRefocus"
        >
          <.notes
            split_of={@split_of}
            transaction={@transaction}
            accounts={@accounts}
            expense_id={@expense_id}
            depot={@depot}
            error={@error}
            sheet
          />
          <.person_select
            :if={@ask_person}
            people={@reimbursement.people}
            value={@params["person_id"]}
          />
          <.amount_field params={@params} fixed={@fixed} target={@myself} invalid={@invalid} />
          <.payee_combo id="tx-payee" side={@main} label {combo_assigns(assigns)} />
          <.category_cell id="tx-category" side={@main} label {combo_assigns(assigns)} />
          <.parts
            :if={@params["split"] == "true"}
            params={@params}
            accounts={@accounts}
            payee_options={@payee_options}
            category_options={@category_options}
            payee_shown={@payee_shown}
            invalid={@invalid}
            target={@myself}
          />
          <div class="grid grid-cols-2 gap-x-4">
            <.input
              id="tx-date"
              type="date"
              form="tx-form"
              name="transaction[date]"
              value={@params["date"]}
              label="Datum"
              required
              disabled={@fixed}
            />
            <.input
              :if={@columns.all}
              id="tx-account"
              type="select"
              form="tx-form"
              name="transaction[account_id]"
              value={@params["account_id"]}
              options={EditorFields.account_options(@accounts, @kept_accounts)}
              label="Konto"
              disabled={@fixed}
            />
          </div>
          <.input
            id="tx-memo"
            form="tx-form"
            name="transaction[memo]"
            value={@params["memo"]}
            label="Memo (optional)"
            autocomplete="off"
            phx-debounce="300"
          />
          <div :if={@transaction && !@fixed} class="mt-3 border-t border-base-content/10 pt-3">
            <.button
              id="tx-delete"
              variant={:ghost}
              icon="trash-2"
              class="-ms-4 text-error-ink"
              confirm={
                if @locked,
                  do: "Diese Buchung ist abgeglichen. Trotzdem löschen?",
                  else: "Buchung löschen?"
              }
              phx-click="delete"
              phx-target={@myself}
              {if @locked, do: ["phx-value-reconciled": "confirmed"], else: []}
            >
              Buchung löschen
            </.button>
          </div>
          <.option_lists payee_options={@payee_options} category_options={@category_options} />
          <.action_bar sticky>
            <.save_buttons
              transaction={@transaction}
              locked={@locked}
              cancel={hide_modal("tx-sheet")}
            />
          </.action_bar>
        </.form>
      </.modal>
    </div>
    """
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(
        subtransactions: TransactionForm.subtransactions(assigns.params),
        remainder: TransactionForm.remainder(assigns.params)
      )
      |> EditorFields.assign_options()

    ~H"""
    <tbody
      id={@id}
      class="app-edit"
      phx-hook="EditRow"
      data-focus={@focus}
    >
      <tr class="app-edit-main" aria-current="true">
        <td colspan={@columns.count}>
          <.form
            for={%{}}
            id="tx-form"
            class="app-edit-grid"
            phx-change="change"
            phx-submit="save"
            phx-target={@myself}
            phx-hook="AmountRefocus"
          >
            <div class="app-edit-date">
              <.date_input value={@params["date"]} disabled={@fixed} />
            </div>
            <div :if={@columns.all} class="app-konto">
              <.account_select
                options={EditorFields.account_options(@accounts, @kept_accounts)}
                value={@params["account_id"]}
                disabled={@fixed}
              />
            </div>
            <div class="app-payee">
              <.payee_combo id="tx-payee" side={@main} small {combo_assigns(assigns)} />
              <.category_below
                id="tx-category"
                side={@main}
                columns={@columns}
                {combo_assigns(assigns)}
              />
            </div>
            <div :if={@columns.category} class="app-catcol">
              <.category_cell id="tx-category" side={@main} small {combo_assigns(assigns)} />
            </div>
            <div class="app-memo-col">
              <.memo_input id="tx-memo" name="transaction[memo]" value={@params["memo"]} />
            </div>
            <div class="app-amount">
              <.signed_amount
                id="tx"
                side={@main}
                values={@params}
                invalid={@invalid[@main]}
                disabled={@fixed}
                target={@myself}
              />
            </div>
            <input :if={@locked} type="hidden" name="reconciled" value="confirmed" />
            <.option_lists payee_options={@payee_options} category_options={@category_options} />
          </.form>
        </td>
      </tr>
      <tr :for={{index, sub} <- @subtransactions} id={"tx-sub-#{index}"}>
        <td colspan={@columns.count}>
          <div class="app-edit-grid">
            <div class="app-edit-date text-end">
              <.remove_button index={index} target={@myself} />
            </div>
            <div class="app-payee">
              <.payee_combo
                :if={own_payee?(@params, index, @payee_shown)}
                id={"tx-sub-#{index}-payee"}
                side={index}
                small
                {combo_assigns(assigns)}
              />
              <.change_payee
                :if={!own_payee?(@params, index, @payee_shown)}
                index={index}
                target={@myself}
              />
              <.category_below
                id={"tx-sub-#{index}-category"}
                side={index}
                columns={@columns}
                {combo_assigns(assigns)}
              />
            </div>
            <div :if={@columns.category} class="app-catcol">
              <.category_cell
                id={"tx-sub-#{index}-category"}
                side={index}
                small
                {combo_assigns(assigns)}
              />
            </div>
            <div class="app-memo-col">
              <.memo_input
                id={"tx-sub-#{index}-memo"}
                name={sub_name(index, "memo")}
                value={sub["memo"]}
                class="app-borderless"
              />
            </div>
            <div class="app-amount">
              <.signed_amount
                id={"tx-sub-#{index}"}
                side={index}
                values={sub}
                invalid={@invalid[index]}
                target={@myself}
              />
            </div>
          </div>
        </td>
      </tr>
      <tr :if={@params["split"] == "true"}>
        <td colspan={@columns.count}>
          <div class="app-edit-grid">
            <div class="app-payee"><.add_button target={@myself} /></div>
            <div class="app-edit-remainder-label text-end text-base-content/70">Noch aufzuteilen</div>
            <div
              id="tx-remainder"
              class={[
                "app-amount text-end",
                if(@remainder in [nil, 0], do: "text-base-content/70", else: "text-error-ink")
              ]}
            >
              {@remainder && Money.signed_amount(@remainder)}
            </div>
          </div>
        </td>
      </tr>
      <tr class="app-edit-foot">
        <td colspan={@columns.count}>
          <div class="app-edit-foot-row">
            <div
              :if={@split_of || @expense_id || @depot || @error || @ask_person}
              class="app-edit-notes"
            >
              <.person_select
                :if={@ask_person}
                people={@reimbursement.people}
                value={@params["person_id"]}
              />
              <.notes
                split_of={@split_of}
                transaction={@transaction}
                accounts={@accounts}
                expense_id={@expense_id}
                depot={@depot}
                error={@error}
              />
            </div>
            <div class="app-edit-buttons">
              <.save_buttons transaction={@transaction} locked={@locked} cancel="cancel_edit" small />
            </div>
          </div>
        </td>
      </tr>
    </tbody>
    """
  end

  attr :split_of, :boolean, required: true
  attr :transaction, :any, required: true
  attr :accounts, :map, required: true
  attr :expense_id, :integer, default: nil
  attr :depot, :boolean, default: false, doc: "whether the Depot leads the transaction"
  attr :error, :string, default: nil
  attr :sheet, :boolean, default: false

  defp notes(assigns) do
    ~H"""
    <p :if={@split_of} id="tx-split-of" class="mr-auto text-sm text-base-content/70">
      Teil einer Aufteilung in {@accounts[@transaction.account_id].name}; hier steht die ganze Aufteilung.
    </p>
    <p :if={@expense_id} id="tx-expense" class="mr-auto text-sm text-base-content/70">
      Aus der Kasse: Betrag, Datum, Konto, Empfänger und Gegenbuchung folgen der <.link
        id="tx-expense-link"
        navigate={~p"/kasse/expenses/#{@expense_id}"}
        class="link link-primary"
      >Ausgabe oder Rückzahlung</.link>.
    </p>
    <p :if={@depot} id="tx-depot" class="mr-auto text-sm text-base-content/70">
      Aus dem Depot: Betrag, Datum und Empfänger folgen der <.link
        id="tx-depot-link"
        navigate={~p"/depot/transactions"}
        class="link link-primary"
      >Buchung im Depot</.link>.
    </p>
    <.alert :if={@error && @sheet} id="tx-error" tone={:error}>{@error}</.alert>
    <p
      :if={@error && !@sheet}
      id="tx-error"
      class="mr-auto flex items-center gap-1 text-sm text-error-ink"
      role="alert"
    >
      <.icon name="circle-alert" class="shrink-0" />{@error}
    </p>
    """
  end

  attr :people, :list, required: true
  attr :value, :any, required: true

  defp person_select(assigns) do
    ~H"""
    <.input
      id="tx-person"
      type="select"
      form="tx-form"
      name="transaction[person_id]"
      value={@value}
      label="Rückzahlung in der Kasse mit"
      prompt="Person wählen"
      options={Enum.map(@people, &{&1.name, &1.id})}
      class="max-w-xs"
    />
    """
  end

  attr :transaction, :any, required: true
  attr :locked, :boolean, required: true
  attr :cancel, :any, required: true, doc: "what Abbrechen does"
  attr :small, :boolean, default: false

  defp save_buttons(%{small: true} = assigns) do
    assigns = assign(assigns, :save_label, save_label(assigns.transaction))

    ~H"""
    <.tooltip id="tx-cancel-tip" text="Abbrechen (Esc)" placement={:left}>
      <.button
        id="tx-cancel"
        variant={:ghost}
        size={:sm}
        icon="x"
        icon_only
        label="Abbrechen"
        phx-click={@cancel}
      />
    </.tooltip>
    <.tooltip id="tx-save-tip" text={"#{@save_label} (Enter)"} placement={:left}>
      <.button
        id="tx-save"
        type="submit"
        form="tx-form"
        variant={:primary}
        size={:sm}
        icon="check"
        icon_only
        label={@save_label}
        confirm={if @locked, do: "Diese Buchung ist abgeglichen. Trotzdem ändern?"}
        confirm_text="Der gebuchte Saldo kann sich dadurch ändern."
        confirm_label="Ändern"
      />
    </.tooltip>
    """
  end

  defp save_buttons(assigns) do
    ~H"""
    <input :if={@locked} type="hidden" name="reconciled" value="confirmed" />
    <.button id="tx-cancel" phx-click={@cancel}>Abbrechen</.button>
    <.button
      id="tx-save"
      type="submit"
      variant={:primary}
      phx-disable-with="Speichern …"
      confirm={if @locked, do: "Diese Buchung ist abgeglichen. Trotzdem ändern?"}
      confirm_text="Der gebuchte Saldo kann sich dadurch ändern."
      confirm_label="Ändern"
    >
      {save_label(@transaction)}
    </.button>
    """
  end

  defp save_label(%Transaction{approved: false}), do: "Bestätigen"
  defp save_label(_transaction), do: "Speichern"

  attr :value, :string, required: true
  attr :disabled, :boolean, default: false

  defp date_input(assigns) do
    ~H"""
    <input
      id="tx-date"
      type="date"
      form="tx-form"
      name="transaction[date]"
      value={@value}
      class="input input-sm"
      aria-label="Datum"
      required
      disabled={@disabled}
    />
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :class, :string, default: nil

  defp memo_input(assigns) do
    ~H"""
    <input
      id={@id}
      form="tx-form"
      name={@name}
      value={@value}
      class={["input input-sm", @class]}
      placeholder="Memo"
      aria-label="Memo"
      autocomplete="off"
      size="1"
      phx-debounce="300"
    />
    """
  end

  attr :options, :list, required: true
  attr :value, :string, required: true
  attr :disabled, :boolean, default: false

  defp account_select(assigns) do
    ~H"""
    <select
      id="tx-account"
      form="tx-form"
      name="transaction[account_id]"
      class="select select-sm"
      aria-label="Konto"
      disabled={@disabled}
    >
      {Phoenix.HTML.Form.options_for_select(@options, @value)}
    </select>
    """
  end

  attr :id, :string, required: true, doc: "prefix of the button's and the field's ids"
  attr :side, :string, required: true
  attr :values, :map, required: true, doc: "the side's params"
  attr :invalid, :any, default: nil, doc: "`{typed, error}` while the amount reads as none"
  attr :disabled, :boolean, default: false
  attr :target, :any, required: true

  # The sign stays out of the tab order, as a sign typed in front sets it too.
  defp signed_amount(assigns) do
    assigns =
      assign(assigns,
        sign: TransactionForm.sign(assigns.values),
        errors: amount_errors(assigns.invalid)
      )

    ~H"""
    <div class="join w-full">
      <.button
        id={"#{@id}-sign"}
        size={:sm}
        disabled={@disabled}
        class={["join-item", @sign == "+" && "text-success-ink"]}
        aria-label={sign_label(@sign)}
        title={sign_label(@sign)}
        tabindex="-1"
        phx-click="toggle_sign"
        phx-value-side={@side}
        phx-target={@target}
      >
        {if @sign == "+", do: "+", else: "−"}
      </.button>
      <input
        id={"#{@id}-amount"}
        form="tx-form"
        name={"#{side_name(@side)}[amount]"}
        value={typed(@invalid) || TransactionForm.directed(@values, @sign)}
        class="input input-sm join-item tabular-nums"
        inputmode="text"
        autocapitalize="off"
        spellcheck="false"
        placeholder="Betrag"
        aria-label="Betrag"
        aria-invalid={@invalid && "true"}
        aria-describedby={describedby("#{@id}-sign", "#{@id}-amount", @errors)}
        autocomplete="off"
        size="1"
        phx-debounce="300"
        phx-blur="check_amount"
        phx-value-side={@side}
        phx-target={@target}
        disabled={@disabled}
      />
    </div>
    <.error_bubble id={"#{@id}-amount"} errors={@errors} align={:end} />
    """
  end

  defp combo_assigns(assigns) do
    Map.take(assigns, [
      :params,
      :accounts,
      :categories,
      :payee_options,
      :category_options,
      :fixed
    ])
  end

  attr :id, :string, required: true
  attr :side, :string, required: true
  attr :columns, :map, required: true
  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :categories, :list, required: true
  attr :payee_options, :list, required: true
  attr :category_options, :list, required: true

  # A tracking account's register has no category column, so a side that takes one shows it below the payee.
  defp category_below(assigns) do
    ~H"""
    <div
      :if={!@columns.category and TransactionForm.category?(@params, @side, @accounts)}
      class="mt-1"
    >
      <.category_cell
        id={@id}
        side={@side}
        small
        params={@params}
        accounts={@accounts}
        category_options={@category_options}
      />
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> EditorState.assign_accounts(assigns.transaction)
      |> assign_fixed()

    key = assigns.transaction && assigns.transaction.id
    socket = if Map.get(socket.assigns, :loaded) == {key}, do: socket, else: load(socket, key)
    {:ok, assign_ask_person(socket)}
  end

  defp assign_fixed(%{assigns: %{current_scope: scope, transaction: transaction}} = socket) do
    led_by = transaction && Ledger.led_by(scope, transaction)

    assign(socket,
      expense_id: expense_id(led_by),
      depot: match?({:depot_transaction, _id}, led_by),
      fixed: led_by != nil
    )
  end

  defp expense_id({:kasse_expense, id}), do: id
  defp expense_id(_led_by), do: nil

  defp load(socket, key) do
    %{transaction: transaction, accounts: accounts} = socket.assigns

    socket
    |> EditorState.load(initial_params(socket.assigns))
    |> assign(
      loaded: {key},
      error: nil,
      invalid: %{},
      locked: locked?(transaction),
      kept_accounts: kept_accounts(transaction, accounts)
    )
    |> assign_reimbursement()
  end

  defp assign_reimbursement(socket) do
    reimbursement = BudgetLink.reimbursement_people(socket.assigns.current_scope)

    assign(socket,
      reimbursement: reimbursement,
      shared_before: shared_transfer?(socket.assigns.params, reimbursement)
    )
  end

  # Only such a transfer dated from the link's start date on becomes a reimbursement.
  defp shared_transfer?(_params, nil), do: false

  defp shared_transfer?(params, %{account_id: shared, start_date: start}) do
    params["split"] != "true" and TransactionForm.transfer?(params) and
      shared in [
        TransactionForm.to_id(params["account_id"]),
        TransactionForm.to_id(params["transfer_account_id"])
      ] and
      started?(params["date"], start)
  end

  defp started?(_date, nil), do: true

  defp started?(date, start) do
    case Date.from_iso8601(date || "") do
      {:ok, date} -> not Date.before?(date, start)
      {:error, _reason} -> true
    end
  end

  defp assign_ask_person(%{assigns: assigns} = socket) do
    ask? =
      match?(%{people: [_, _ | _]}, assigns.reimbursement) and not assigns.fixed and
        not assigns.shared_before and shared_transfer?(assigns.params, assigns.reimbursement)

    assign(socket, :ask_person, ask?)
  end

  defp initial_params(%{transaction: nil} = assigns),
    do:
      TransactionForm.new(
        EditorFields.entry_account_id(assigns.account, assigns.accounts),
        assigns.today
      )

  defp initial_params(%{transaction: transaction}),
    do: TransactionForm.from_transaction(transaction)

  defp sides(nil), do: []
  defp sides(transaction), do: [transaction | transaction.subtransactions]

  @doc "Whether the transaction, one of its parts or a counterpart is reconciled."
  def locked?(transaction) do
    transaction
    |> sides()
    |> Enum.flat_map(&[&1, &1.transfer_transaction])
    |> Enum.any?(&match?(%Transaction{cleared: :reconciled, deleted_at: nil}, &1))
  end

  # Accounts the transaction uses, which stay selectable though closed or fed.
  defp kept_accounts(transaction, accounts),
    do:
      MapSet.intersection(EditorState.used_accounts(transaction), MapSet.new(Map.keys(accounts)))

  @impl true
  def handle_event("change", %{"transaction" => _changed} = event, socket) do
    {:noreply,
     socket
     |> EditorState.change(event)
     |> assign(:error, nil)
     |> retyped(event)
     |> prune_invalid()
     |> assign_ask_person()}
  end

  def handle_event("check_amount", %{"side" => side} = event, socket) do
    text = event["value"] || ""

    case TransactionForm.amount_refusal(text) do
      nil -> {:noreply, update(socket, :invalid, &Map.delete(&1, side))}
      refusal -> {:noreply, refuse_amounts(socket, [{side, text, refusal}])}
    end
  end

  def handle_event("save", event, socket) do
    %{accounts: accounts, transaction: original} = socket.assigns
    params = EditorState.submitted(socket, event)

    opts = confirmed(event) ++ [person_id: person_id(params["person_id"])]
    socket = assign(socket, invalid: %{})

    with [] <- TransactionForm.refused_amounts(params),
         {:ok, attrs} <- TransactionForm.to_attrs(params, accounts, original),
         {:ok, attrs} <- register_fields(attrs, socket.assigns),
         {:ok, _transaction} <-
           BudgetLink.write_from_register(socket.assigns.current_scope, original, attrs, opts) do
      {:noreply, done(socket, "Gespeichert.")}
    else
      [_ | _] = refused ->
        {:noreply,
         socket
         |> assign(params: params, error: nil)
         |> refuse_amounts(as_typed(refused, event["transaction"] || %{}))
         |> assign_ask_person()}

      {:error, error} ->
        {:noreply,
         socket |> assign(params: params, error: error_message(error)) |> assign_ask_person()}
    end
  end

  def handle_event("delete", _event, %{assigns: %{expense_id: id}} = socket) when id != nil,
    do: {:noreply, assign(socket, :error, @linked_delete)}

  def handle_event("delete", _event, %{assigns: %{depot: true}} = socket),
    do: {:noreply, assign(socket, :error, @depot_delete)}

  def handle_event("delete", event, socket) do
    %{current_scope: current_scope, transaction: transaction} = socket.assigns

    case Ledger.delete_transaction(current_scope, transaction, confirmed(event)) do
      {:ok, _transaction} -> {:noreply, done(socket, "Buchung gelöscht.")}
      {:error, changeset} -> {:noreply, assign(socket, :error, error_message(changeset))}
    end
  end

  def handle_event(event, params, socket),
    do: {:noreply, event |> EditorState.handle_event(params, socket) |> prune_invalid()}

  # The params keep a typed sign apart from the digits; the field sent both.
  defp as_typed(refused, changed) do
    Enum.map(refused, fn {side, text, refusal} ->
      {side, side_changes(changed, side)["amount"] || text, refusal}
    end)
  end

  defp side_changes(changed, @main), do: changed
  defp side_changes(changed, index), do: get_in(changed, ["subtransactions", index]) || %{}

  # The change a blur flushes carries the refused text again, which keeps its refusal.
  defp retyped(socket, %{"_target" => target} = event) do
    with side when side != nil <- amount_side(target),
         {typed, _error} <- socket.assigns.invalid[side],
         false <- get_in(event, target) == typed do
      update(socket, :invalid, &Map.delete(&1, side))
    else
      _kept -> socket
    end
  end

  defp retyped(socket, _event), do: socket

  defp amount_side(["transaction", "amount"]), do: @main

  defp amount_side(["transaction", "subtransactions", index, field])
       when field in ~w(amount outflow inflow),
       do: index

  defp amount_side(_target), do: nil

  # A part made anew under an index that was refused before starts without its refusal.
  defp prune_invalid(%{assigns: %{params: params}} = socket) do
    parts = if params["split"] == "true", do: Map.keys(params["subtransactions"] || %{}), else: []
    update(socket, :invalid, &Map.take(&1, [@main | parts]))
  end

  defp refuse_amounts(socket, [{first, _text, _refusal} | _rest] = refused) do
    socket
    |> update(:invalid, fn invalid ->
      Enum.reduce(refused, invalid, fn {side, text, refusal}, invalid ->
        Map.put(invalid, side, {text, refused_amount(text, refusal)})
      end)
    end)
    |> push_event("refocus_amount", %{id: amount_id(first)})
  end

  defp refused_amount(_text, :out_of_range), do: BudgetComponents.out_of_range_amount()
  defp refused_amount(text, :invalid), do: BudgetComponents.invalid_amount(text)

  defp amount_id(@main), do: "tx-amount"
  defp amount_id(index), do: "tx-sub-#{index}-amount"

  defp register_fields(attrs, %{fixed: false}), do: {:ok, attrs}

  defp register_fields(%{subtransactions: [_ | _]}, %{depot: true}),
    do: {:error, "Eine Buchung aus dem Depot lässt sich nicht aufteilen."}

  defp register_fields(%{subtransactions: [_ | _]}, _assigns),
    do: {:error, "Eine Buchung aus der Kasse lässt sich nicht aufteilen."}

  defp register_fields(attrs, _assigns),
    do: {:ok, Map.drop(attrs, [:payee_name | Ledger.led_fields()])}

  @doc "The Ledger's opts for an event: `reconciled: :confirmed` once the browser asked about a reconciled change."
  def confirmed(%{"reconciled" => "confirmed"}), do: [reconciled: :confirmed]
  def confirmed(_event), do: []

  defp person_id(param) do
    case Abakus.Schema.cast_id(param) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp done(socket, message) do
    send(self(), {__MODULE__, :done, message})
    socket
  end

  @doc "The errors of a transaction's changeset as one text, each with its field's label and a split's by part."
  def error_message(text) when is_binary(text), do: text
  def error_message(:not_a_proposal), do: "Der Zuordnungsvorschlag ist schon entschieden."

  def error_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> messages(nil)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp messages(errors, prefix) when is_map(errors) do
    Enum.flat_map(errors, fn
      {:subtransactions, parts} when is_list(parts) ->
        parts
        |> Enum.with_index(1)
        |> Enum.flat_map(fn
          {part, number} when is_map(part) -> messages(part, "Teil #{number}: ")
          {text, _number} -> ["Aufteilung: #{text}"]
        end)

      {field, texts} ->
        Enum.map(texts, &"#{prefix}#{Map.get(@labels, field, "Buchung")} #{&1}")
    end)
  end
end

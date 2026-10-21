defmodule AbakusWeb.RegisterLive.TransactionEditor do
  @moduledoc """
  Edits a transaction as YNAB does, for a new one and an existing one alike. On desktops (`layout: :row`) it
  replaces the transaction's rows in the register on one line: inputs in every column, Cancel and Save (Approve for
  one waiting for approval) where approve and status stand, Enter saves and Escape cancels; a split's subtransactions as
  rows below, each with a payee field only where it differs from the transaction's. Its root is a `<tbody>`, the
  inputs outside the first row belong to `#tx-form` by their `form` attribute. Phones (`layout: :sheet`) get a sheet
  from the bottom with the amount first. The form's state is `AbakusWeb.TransactionForm` params.

  Payee and category are Setzkasten comboboxes; a choice arrives as a change of `payee_pick` (with `payee_new` for a
  payee typed anew) or `category_pick`, "Aufteilen" among the categories splits the transaction. Transfers are picked as
  payees, the other open accounts above the payees, in a split's subtransactions too. A payee suggests its last
  category, and a suggestion goes again when the payee changes; a chosen category stays. A transfer between a budget and
  a tracking account takes a category and suggests the one last used between the two. Changing or deleting a reconciled
  transaction, or one whose counterpart is, asks first. A transaction its source leads (`Ledger.led_by/2`, ADR 0020)
  links to its Kasse expense or Depot transaction and keeps what the source leads (`Ledger.led_fields/0`); it is
  neither split nor deleted here. So does a value change the Depot booked.

  Tells its LiveView `{TransactionEditor, :done, message}` once the transaction is saved or deleted; the events
  `cancel_edit` (Cancel, Escape) go to the LiveView itself.
  """
  use AbakusWeb, :live_component

  alias Abakus.{Categories, Ledger, Names}
  alias Abakus.Ledger.{Account, Transaction}
  alias Abakus.Money
  alias AbakusWeb.{AccountGroups, CategoryOptions, TransactionForm}

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
    assigns =
      assigns
      |> assign(:subtransactions, TransactionForm.subtransactions(assigns.params))
      |> assign_options()

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
          <fieldset class="fieldset min-w-0">
            <label class="fieldset-legend" for="tx-amount">Betrag</label>
            <div class="join w-full">
              <.button
                id="tx-sign"
                disabled={@fixed}
                class={["join-item app-sign", sign_class(@params["sign"])]}
                aria-label={sign_label(@params["sign"])}
                title={sign_label(@params["sign"])}
                phx-click="toggle_sign"
                phx-target={@myself}
              >
                {if @params["sign"] == "+", do: "+", else: "−"}
              </.button>
              <label class="input join-item w-full">
                <.directed_amount
                  id="tx-amount"
                  name="transaction"
                  side={@params}
                  sign={@params["sign"]}
                  disabled={@fixed}
                  class="text-end tabular-nums app-tx-amount-input"
                />
                <span class="label">€</span>
              </label>
            </div>
          </fieldset>
          <.payee_combo id="tx-payee" side={@main} label {combo_assigns(assigns)} />
          <.category_cell id="tx-category" side={@main} label {combo_assigns(assigns)} />
          <div :if={@params["split"] == "true"} class="flex flex-col gap-2 py-2">
            <div
              :for={{index, sub} <- @subtransactions}
              id={"tx-sub-#{index}"}
              class="flex flex-col gap-2 rounded-box border border-base-content/10 p-3"
            >
              <div class="flex items-center gap-2">
                <div class="min-w-0 grow">
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
                </div>
                <.remove_button index={index} target={@myself} />
              </div>
              <.category_cell id={"tx-sub-#{index}-category"} side={index} {combo_assigns(assigns)} />
              <div class="flex gap-2">
                <input
                  id={"tx-sub-#{index}-memo"}
                  form="tx-form"
                  name={sub_name(index, "memo")}
                  value={sub["memo"]}
                  class="input min-w-0 grow"
                  placeholder="Memo"
                  aria-label="Memo"
                  autocomplete="off"
                  phx-debounce="300"
                />
                <label class="input w-36 shrink-0">
                  <.directed_amount
                    id={"tx-sub-#{index}-amount"}
                    name={sub_name(index)}
                    side={sub}
                    sign={@params["sign"]}
                    class="text-end tabular-nums"
                  />
                  <span class="label">€</span>
                </label>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <.add_button target={@myself} />
              <span id="tx-remainder" class="ml-auto text-sm tabular-nums">
                <.remainder amount={directed_remainder(@params)} />
              </span>
            </div>
          </div>
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
              options={account_options(assigns)}
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
      |> assign_options()

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
          >
            <div class="app-edit-date">
              <.date_input value={@params["date"]} disabled={@fixed} />
            </div>
            <div :if={@columns.all} class="app-konto">
              <.account_select
                options={account_options(assigns)}
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
            <div class="app-out">
              <.amount_input
                id="tx-outflow"
                name="transaction[outflow]"
                value={@params["outflow"]}
                placeholder="Ausgang"
                disabled={@fixed}
              />
            </div>
            <div class="app-in">
              <.amount_input
                id="tx-inflow"
                name="transaction[inflow]"
                value={@params["inflow"]}
                placeholder="Eingang"
                disabled={@fixed}
              />
            </div>
            <div class="app-edit-buttons">
              <.save_buttons transaction={@transaction} locked={@locked} cancel="cancel_edit" small />
            </div>
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
            <div class="app-out">
              <.amount_input
                id={"tx-sub-#{index}-outflow"}
                name={sub_name(index, "outflow")}
                value={sub["outflow"]}
                placeholder="Ausgang"
              />
            </div>
            <div class="app-in">
              <.amount_input
                id={"tx-sub-#{index}-inflow"}
                name={sub_name(index, "inflow")}
                value={sub["inflow"]}
                placeholder="Eingang"
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
              id="tx-remainder-out"
              class={["app-out text-end", remainder_class(@remainder && -@remainder)]}
            >
              {@remainder && Money.amount(max(-@remainder, 0))}
            </div>
            <div id="tx-remainder-in" class={["app-in text-end", remainder_class(@remainder)]}>
              {@remainder && Money.amount(max(@remainder, 0))}
            </div>
          </div>
        </td>
      </tr>
      <tr :if={@split_of || @expense_id || @depot || @error} class="app-edit-notes">
        <td colspan={@columns.count}>
          <.notes
            split_of={@split_of}
            transaction={@transaction}
            accounts={@accounts}
            expense_id={@expense_id}
            depot={@depot}
            error={@error}
          />
        </td>
      </tr>
    </tbody>
    """
  end

  attr :split_of, :boolean, required: true
  attr :transaction, :any, required: true
  attr :accounts, :map, required: true
  attr :expense_id, :integer, default: nil
  attr :depot, :atom, default: nil, doc: "`:value_change` or `:linked` for what the Depot booked"
  attr :error, :string, default: nil
  attr :sheet, :boolean, default: false

  defp notes(assigns) do
    ~H"""
    <p :if={@split_of} id="tx-split-of" class="mr-auto text-sm text-base-content/70">
      Teil einer Aufteilung in {@accounts[@transaction.account_id].name}; hier steht die ganze Aufteilung.
    </p>
    <p :if={@expense_id} id="tx-expense" class="mr-auto text-sm text-base-content/70">
      Was eine Ausgabe der Kasse an deinem Saldo ändert: Betrag, Datum und Empfänger folgen der <.link
        id="tx-expense-link"
        navigate={~p"/kasse/expenses/#{@expense_id}"}
        class="link link-primary"
      >Ausgabe</.link>.
    </p>
    <p :if={@depot == :value_change} id="tx-depot" class="mr-auto text-sm text-base-content/70">
      Wertänderung des Depots: Betrag, Datum und Empfänger bucht das Depot.
    </p>
    <p :if={@depot == :linked} id="tx-depot" class="mr-auto text-sm text-base-content/70">
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

  attr :transaction, :any, required: true
  attr :locked, :boolean, required: true
  attr :cancel, :any, required: true, doc: "what Abbrechen does"
  attr :small, :boolean, default: false

  defp save_buttons(%{small: true} = assigns) do
    assigns = assign(assigns, :save_label, save_label(assigns.transaction))

    ~H"""
    <input :if={@locked} type="hidden" name="reconciled" value="confirmed" />
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

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :placeholder, :string, required: true
  attr :disabled, :boolean, default: false

  defp amount_input(assigns) do
    ~H"""
    <input
      id={@id}
      form="tx-form"
      name={@name}
      value={@value}
      class="input input-sm text-end tabular-nums"
      inputmode="decimal"
      placeholder={@placeholder}
      aria-label={@placeholder}
      autocomplete="off"
      size="1"
      phx-debounce="300"
      disabled={@disabled}
    />
    """
  end

  # The phone's one amount: the column the sign picks, the other one emptied.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :side, :map, required: true
  attr :sign, :string, required: true
  attr :class, :string, required: true
  attr :disabled, :boolean, default: false

  defp directed_amount(assigns) do
    {column, other} =
      if assigns.sign == "+", do: {"inflow", "outflow"}, else: {"outflow", "inflow"}

    assigns = assign(assigns, column: column, other: other)

    ~H"""
    <input type="hidden" form="tx-form" name={"#{@name}[#{@other}]"} value="" />
    <input
      id={@id}
      form="tx-form"
      name={"#{@name}[#{@column}]"}
      value={TransactionForm.directed(@side, @sign)}
      class={@class}
      inputmode="decimal"
      placeholder="0,00"
      aria-label="Betrag"
      autocomplete="off"
      phx-debounce="300"
      disabled={@disabled}
    />
    """
  end

  attr :index, :string, required: true
  attr :target, :any, required: true

  defp remove_button(assigns) do
    ~H"""
    <.button
      id={"tx-sub-#{@index}-remove"}
      variant={:ghost}
      size={:sm}
      icon="x"
      icon_only
      label="Teil entfernen"
      title="Teil entfernen"
      phx-click="remove_subtransaction"
      phx-value-index={@index}
      phx-target={@target}
    />
    """
  end

  attr :index, :string, required: true
  attr :target, :any, required: true

  defp change_payee(assigns) do
    ~H"""
    <.button
      id={"tx-sub-#{@index}-change-payee"}
      variant={:ghost}
      size={:sm}
      class="font-normal text-base-content/70"
      phx-click="show_sub_payee"
      phx-value-index={@index}
      phx-target={@target}
    >
      Empfänger ändern
    </.button>
    """
  end

  # A part has a payee field of its own only where it differs from the transaction's, or once asked for.
  defp own_payee?(params, index, shown) do
    part = TransactionForm.side(params, index)

    index in shown or TransactionForm.transfer?(part) or
      part["payee"] not in [nil, "", params["payee"]]
  end

  attr :target, :any, required: true

  defp add_button(assigns) do
    ~H"""
    <.button
      id="tx-add-sub"
      variant={:ghost}
      size={:sm}
      icon="plus"
      phx-click="add_subtransaction"
      phx-target={@target}
    >
      Teil hinzufügen
    </.button>
    """
  end

  attr :amount, :integer, default: nil

  defp remainder(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@amount) -> %>
      <% @amount == 0 -> %>
        <span class="text-success-ink">Aufteilung stimmt</span>
      <% true -> %>
        Noch aufzuteilen:
        <.amount value={@amount} class={["font-semibold", @amount < 0 && "text-error-ink"]} />
    <% end %>
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

  # The comboboxes' options, the same for every side: transfers to the other open accounts above the payees.
  defp assign_options(assigns) do
    transfers =
      for account <- transfer_options(assigns.params, assigns.accounts),
          do: %{label: TransactionForm.transfer_label(account), value: "a:#{account.id}"}

    payees = for payee <- assigns.payees, do: %{label: payee.name, value: "p:#{payee.name}"}

    categories =
      for group <- assigns.categories do
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

    assign(assigns,
      payee_options:
        if(transfers == [], do: [], else: [{"Umbuchungen", transfers}]) ++
          [{"Empfänger", payees}],
      category_options: categories
    )
  end

  attr :id, :string, required: true
  attr :side, :string, required: true
  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :payee_options, :list, required: true
  attr :fixed, :boolean, default: false
  attr :label, :boolean, default: false
  attr :small, :boolean, default: false

  defp payee_combo(assigns) do
    side = TransactionForm.side(assigns.params, assigns.side)
    prefix = side_name(assigns.side)

    {value, created} =
      cond do
        TransactionForm.transfer?(side) ->
          {"a:#{side["transfer_account_id"]}", ""}

        Enum.any?(assigns.payee_options, fn {_group, options} ->
          Enum.any?(options, &(&1.value == "p:#{side["payee"]}"))
        end) ->
          {"p:#{side["payee"]}", ""}

        true ->
          {"", side["payee"] || ""}
      end

    assigns =
      assign(assigns,
        name: "#{prefix}[payee_pick]",
        value: value,
        created: %Phoenix.HTML.FormField{
          id: "#{assigns.id}-new",
          name: "#{prefix}[payee_new]",
          value: created,
          errors: [],
          field: :payee_new,
          form: nil
        }
      )

    ~H"""
    <.combobox
      id={@id}
      name={@name}
      value={@value}
      label="Empfänger"
      hide_label={!@label}
      options={@payee_options}
      options_from="tx-payee-list"
      placeholder="Empfänger"
      allow_create
      create_label="Empfänger „%{text}“ anlegen"
      create_field={@created}
      class={@small && "input-sm"}
      form="tx-form"
      disabled={@fixed}
    />
    """
  end

  attr :id, :string, required: true
  attr :side, :string, required: true
  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :category_options, :list, required: true
  attr :fixed, :boolean, default: false
  attr :label, :boolean, default: false
  attr :small, :boolean, default: false

  # The category of a side: a combobox where it takes one, else what stands there instead. "Aufteilen" is offered
  # for the transaction's own category only.
  defp category_cell(assigns) do
    side = TransactionForm.side(assigns.params, assigns.side)
    main? = assigns.side == "main"

    assigns =
      assign(assigns,
        values: side,
        category?: TransactionForm.category?(assigns.params, assigns.side, assigns.accounts),
        split?: main? and assigns.params["split"] == "true",
        splittable?: main? and !TransactionForm.transfer?(side) and !assigns.fixed
      )

    ~H"""
    <%= cond do %>
      <% @split? -> %>
        <span id={@id} class="block truncate text-base-content/70">
          Aufgeteilt (mehrere Kategorien)
        </span>
      <% !@category? -> %>
        <input
          id={@id}
          type="text"
          class={[
            "input w-full border-transparent bg-transparent shadow-none",
            @small && "input-sm"
          ]}
          placeholder={none_placeholder(@values)}
          aria-label="Kategorie"
          size="1"
          readonly
          tabindex="-1"
        />
      <% true -> %>
        <.combobox
          id={@id}
          name={"#{side_name(@side)}[category_pick]"}
          value={@values["category_id"]}
          label="Kategorie"
          hide_label={!@label}
          options={@category_options}
          options_from={if @splittable?, do: "tx-category-split-list", else: "tx-category-list"}
          placeholder="Kategorie"
          class={@small && "input-sm"}
          form="tx-form"
        />
    <% end %>
    """
  end

  attr :payee_options, :list, required: true
  attr :category_options, :list, required: true

  # The option lists every side's comboboxes copy in; "Aufteilen" only for the transaction's own category.
  defp option_lists(assigns) do
    ~H"""
    <.combobox_options id="tx-payee-list" options={@payee_options} />
    <.combobox_options
      :for={
        {id, options} <- [
          {"tx-category-list", @category_options},
          {"tx-category-split-list", @category_options ++ [%{label: "Aufteilen", value: "split"}]}
        ]
      }
      id={id}
      options={options}
    >
      <:option :let={option}>
        <span :if={option.value == "split"} class="flex flex-1 items-center gap-2 text-primary">
          <.icon name="plus" class="size-4" />Aufteilen
        </span>
        <span :if={option.value != "split"} class="min-w-0 flex-1 truncate">{option.name}</span>
        <.amount :if={option.value != "split"} value={option.available} tone />
      </:option>
    </.combobox_options>
    """
  end

  attr :id, :string, required: true
  attr :side, :string, required: true
  attr :columns, :map, required: true
  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :categories, :list, required: true
  attr :payee_options, :list, required: true
  attr :category_options, :list, required: true

  # A tracking account's register has no category column, so a side that takes one there (a transfer to a budget
  # account, or a part of a split opened from its counterpart) has it below the payee.
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

  defp none_placeholder(side) do
    if TransactionForm.transfer?(side), do: "Keine Kategorie nötig", else: ""
  end

  defp remainder_class(left) when is_integer(left) and left > 0, do: "text-error-ink"
  defp remainder_class(_none), do: "text-base-content/70"

  defp side_name(@main), do: "transaction"
  defp side_name(index), do: sub_name(index)

  defp sub_name(index), do: "transaction[subtransactions][#{index}]"
  defp sub_name(index, field), do: "#{sub_name(index)}[#{field}]"

  @impl true
  def update(assigns, socket) do
    socket = socket |> assign(assigns) |> assign_fixed()
    key = assigns.transaction && assigns.transaction.id

    if Map.get(socket.assigns, :loaded) == {key},
      do: {:ok, socket},
      else: {:ok, load(socket, key)}
  end

  defp assign_fixed(%{assigns: %{current_scope: scope, transaction: transaction}} = socket) do
    led_by = transaction && Ledger.led_by(scope, transaction)
    depot = depot(transaction, led_by)

    assign(socket,
      expense_id: expense_id(led_by),
      depot: depot,
      fixed: led_by != nil or depot != nil
    )
  end

  defp expense_id({:kasse_expense, id}), do: id
  defp expense_id(_led_by), do: nil

  defp depot(_transaction, {:depot_transaction, _id}), do: :linked
  defp depot(%Transaction{source: :depot}, nil), do: :value_change
  defp depot(_transaction, _led_by), do: nil

  defp load(socket, key) do
    %{transaction: transaction, accounts: accounts} = socket.assigns
    payees = Ledger.list_payees(socket.assigns.current_scope)

    assign(socket,
      loaded: {key},
      main: @main,
      params: initial_params(socket.assigns),
      suggested: MapSet.new(),
      payee_shown: MapSet.new(),
      error: nil,
      payees: payees,
      payees_by_key: Map.new(payees, &{&1.lookup_key, &1}),
      ready_to_assign_id: Categories.ready_to_assign!(socket.assigns.current_scope).id,
      categories: CategoryOptions.build(socket.assigns.current_scope, socket.assigns.today),
      locked: locked?(transaction),
      kept_accounts: kept_accounts(transaction, accounts)
    )
  end

  defp initial_params(%{transaction: nil} = assigns),
    do: TransactionForm.new(default_account_id(assigns), assigns.today)

  defp initial_params(%{transaction: transaction}),
    do: TransactionForm.from_transaction(transaction)

  # The register's account if it takes manual entries, else the first that does, budget accounts first.
  defp default_account_id(%{account: account, accounts: accounts}) do
    if account && Account.takes_entries?(account) do
      account.id
    else
      case accounts
           |> Map.values()
           |> Enum.filter(&Account.takes_entries?/1)
           |> groups()
           |> AccountGroups.rows() do
        [%{account: first} | _rest] -> first.id
        [] -> nil
      end
    end
  end

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
  defp kept_accounts(transaction, accounts) do
    sides(transaction)
    |> Enum.map(&(&1.payee && &1.payee.transfer_account_id))
    |> then(&[transaction && transaction.account_id | &1])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(Map.keys(accounts)))
  end

  @impl true
  def handle_event("change", %{"transaction" => changed} = event, socket) do
    {picks, changed} = picks(changed)
    params = TransactionForm.change(socket.assigns.params, changed, socket.assigns.accounts)

    socket =
      case pick_target(event["_target"]) do
        {side, field} -> socket |> assign(:params, params) |> pick(side, field, picks[side])
        nil -> after_change(socket, params, event["_target"])
      end

    {:noreply, assign(socket, :error, nil)}
  end

  def handle_event("split", _params, socket),
    do: {:noreply, update(socket, :params, &TransactionForm.split/1)}

  def handle_event("toggle_sign", _params, socket) do
    params = TransactionForm.toggle_sign(socket.assigns.params)
    {:noreply, directed(socket, params)}
  end

  def handle_event("show_sub_payee", %{"index" => index}, socket),
    do: {:noreply, update(socket, :payee_shown, &MapSet.put(&1, index))}

  def handle_event("add_subtransaction", _params, socket),
    do: {:noreply, update(socket, :params, &TransactionForm.add_subtransaction/1)}

  def handle_event("remove_subtransaction", %{"index" => index}, socket),
    do: {:noreply, update(socket, :params, &TransactionForm.remove_subtransaction(&1, index))}

  def handle_event("save", event, socket) do
    %{accounts: accounts, transaction: original} = socket.assigns
    {_picks, changed} = picks(event["transaction"] || %{})
    params = TransactionForm.change(socket.assigns.params, changed, accounts)

    with {:ok, attrs} <- TransactionForm.to_attrs(params, accounts, original),
         {:ok, attrs} <- register_fields(attrs, socket.assigns),
         {:ok, _transaction} <-
           write(socket.assigns.current_scope, original, attrs, confirmed(event)) do
      {:noreply, done(socket, "Gespeichert.")}
    else
      {:error, error} -> {:noreply, assign(socket, params: params, error: error_message(error))}
    end
  end

  def handle_event("delete", _event, %{assigns: %{expense_id: id}} = socket) when id != nil,
    do: {:noreply, assign(socket, :error, @linked_delete)}

  def handle_event("delete", _event, %{assigns: %{depot: depot}} = socket) when depot != nil,
    do: {:noreply, assign(socket, :error, @depot_delete)}

  def handle_event("delete", event, socket) do
    %{current_scope: current_scope, transaction: transaction} = socket.assigns

    case Ledger.delete_transaction(current_scope, transaction, confirmed(event)) do
      {:ok, _transaction} -> {:noreply, done(socket, "Buchung gelöscht.")}
      {:error, changeset} -> {:noreply, assign(socket, :error, error_message(changeset))}
    end
  end

  @picks ~w(payee_pick payee_new category_pick)

  # What the comboboxes chose, by side, apart from what was typed.
  defp picks(changed) do
    subs = changed["subtransactions"] || %{}

    picks =
      Map.new(subs, fn {index, sub} -> {index, Map.take(sub, @picks)} end)
      |> Map.put(@main, Map.take(changed, @picks))

    subs = Map.new(subs, fn {index, sub} -> {index, Map.drop(sub, @picks)} end)

    changed =
      changed
      |> Map.drop(@picks)
      |> then(&if(&1["subtransactions"], do: Map.put(&1, "subtransactions", subs), else: &1))

    {picks, changed}
  end

  defp pick_target(["transaction", field]) when field in ["payee_pick", "category_pick"],
    do: {@main, field}

  defp pick_target(["transaction", "subtransactions", index, field])
       when field in ["payee_pick", "category_pick"],
       do: {index, field}

  defp pick_target(_target), do: nil

  defp pick(socket, side, "payee_pick", picked) do
    %{params: params, accounts: accounts} = socket.assigns

    case picked || %{} do
      %{"payee_pick" => "a:" <> id} ->
        params = TransactionForm.pick_payee(params, side, {:transfer, id})

        suggest(
          socket,
          params,
          side,
          socket.assigns.current_scope
          |> transfer_category(params, side, accounts)
          |> suggest_offered(socket)
        )

      %{"payee_pick" => "p:" <> name} ->
        payee(socket, params, side, name)

      picked ->
        payee(socket, params, side, picked["payee_new"] || "")
    end
  end

  defp pick(socket, side, "category_pick", %{"category_pick" => "split"}) when side == @main,
    do: update(socket, :params, &TransactionForm.split/1)

  defp pick(socket, side, "category_pick", %{"category_pick" => id}) do
    cond do
      id == "" ->
        put_category(socket, side, "")

      TransactionForm.to_id(id) in CategoryOptions.ids(socket.assigns.categories) ->
        put_category(socket, side, id)

      true ->
        socket
    end
  end

  defp pick(socket, _side, _field, _picked), do: socket

  defp payee(socket, params, side, name) do
    name = String.trim(name)
    params = TransactionForm.pick_payee(params, side, {:payee, name})
    suggest(socket, params, side, payee_category(socket, name))
  end

  defp put_category(socket, side, id) do
    params = TransactionForm.put_side(socket.assigns.params, side, %{"category_id" => id})
    assign(socket, params: params, suggested: MapSet.delete(socket.assigns.suggested, side))
  end

  defp after_change(socket, params, ["transaction", column]) when column in ["outflow", "inflow"],
    do: directed(socket, TransactionForm.keep_column(params, @main, column))

  defp after_change(socket, params, ["transaction", "subtransactions", index, column])
       when column in ["outflow", "inflow"],
       do: assign(socket, :params, TransactionForm.keep_column(params, index, column))

  defp after_change(socket, params, _target), do: assign(socket, :params, params)

  defp directed(socket, params) do
    params = TransactionForm.follow_direction(params, socket.assigns.ready_to_assign_id)
    suggested = socket.assigns.suggested

    suggested =
      if params["category_id"] == "", do: MapSet.delete(suggested, @main), else: suggested

    assign(socket, params: params, suggested: suggested)
  end

  defp suggest(socket, params, side, category_id) do
    suggested? = MapSet.member?(socket.assigns.suggested, side)
    {params, suggested} = TransactionForm.suggest(params, side, category_id, suggested?)
    set = if suggested, do: &MapSet.put/2, else: &MapSet.delete/2
    assign(socket, params: params, suggested: set.(socket.assigns.suggested, side))
  end

  defp payee_category(socket, name) do
    case Map.get(socket.assigns.payees_by_key, Names.lookup_key(name)) do
      %{last_category_id: id} -> offered(socket, id)
      nil -> nil
    end
  end

  defp transfer_category(current_scope, params, side, accounts) do
    case TransactionForm.crossing(params, side, accounts) do
      {budget, tracking} ->
        Ledger.last_transfer_category_id(current_scope, budget.id, tracking.transfer_payee.id)

      nil ->
        nil
    end
  end

  defp suggest_offered(nil, _socket), do: nil
  defp suggest_offered(id, socket), do: offered(socket, id)

  defp offered(socket, id), do: if(id in CategoryOptions.ids(socket.assigns.categories), do: id)

  defp register_fields(attrs, %{fixed: false}), do: {:ok, attrs}

  defp register_fields(%{subtransactions: [_ | _]}, %{depot: depot}) when depot != nil,
    do: {:error, "Eine Buchung aus dem Depot lässt sich nicht aufteilen."}

  defp register_fields(%{subtransactions: [_ | _]}, _assigns),
    do: {:error, "Eine Buchung aus der Kasse lässt sich nicht aufteilen."}

  defp register_fields(attrs, _assigns),
    do: {:ok, Map.drop(attrs, [:payee_name | Ledger.led_fields()])}

  defp write(current_scope, nil, attrs, _opts),
    do: Ledger.create_transaction(current_scope, attrs)

  defp write(current_scope, original, attrs, opts),
    do: Ledger.update_transaction(current_scope, original, attrs, opts)

  @doc "The Ledger's opts for an event: `reconciled: :confirmed` once the browser asked about a reconciled change."
  def confirmed(%{"reconciled" => "confirmed"}), do: [reconciled: :confirmed]
  def confirmed(_event), do: []

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

  # The split's subtransactions have errors of their own each, or the split has them as a whole.
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

  defp account_options(assigns) do
    assigns.accounts
    |> Map.values()
    |> Enum.filter(&(Account.takes_entries?(&1) or &1.id in assigns.kept_accounts))
    |> grouped()
  end

  # The other open accounts (and the closed ones the transaction uses), as the sidebar orders them.
  defp transfer_options(params, accounts) do
    own_id = TransactionForm.to_id(params["account_id"])

    used =
      [params | Enum.map(TransactionForm.subtransactions(params), &elem(&1, 1))]
      |> Enum.map(&TransactionForm.to_id(&1["transfer_account_id"]))

    accounts
    |> Map.values()
    |> Enum.filter(&((not &1.closed or &1.id in used) and &1.id != own_id))
    |> groups()
    |> AccountGroups.rows()
    |> Enum.map(& &1.account)
  end

  defp grouped(accounts) do
    for group <- groups(accounts),
        do: {group.label, Enum.map(group.rows, &{&1.account.name, &1.account.id})}
  end

  # The accounts grouped and ordered as in the sidebar.
  defp groups(accounts),
    do: accounts |> Enum.sort_by(&{&1.position, &1.id}) |> AccountGroups.build(%{})

  defp directed_remainder(params) do
    case TransactionForm.remainder(params) do
      nil -> nil
      left -> if params["sign"] == "+", do: left, else: -left
    end
  end

  defp sign_class("+"), do: "text-success-ink"
  defp sign_class(_sign), do: "text-error-ink"

  defp sign_label("+"), do: "Eingang, umschalten auf Ausgang"
  defp sign_label(_sign), do: "Ausgang, umschalten auf Eingang"
end

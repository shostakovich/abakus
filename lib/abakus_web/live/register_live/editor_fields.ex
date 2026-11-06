defmodule AbakusWeb.RegisterLive.EditorFields do
  @moduledoc """
  The fields the transaction editor (`AbakusWeb.RegisterLive.TransactionEditor`) and the scheduled transaction's
  dialog (`AbakusWeb.RegisterLive.ScheduledDialog`) share, over `AbakusWeb.TransactionForm` params kept by
  `AbakusWeb.RegisterLive.EditorState`: payee and category comboboxes with the option lists they share, the amount
  behind its sign and a split's parts as the phone sheet shows them. `prefix` names the form (`<prefix>-form`) and
  starts every id, "tx" by default.

  Transfers are picked as payees, the other open accounts above the payees, in a split's parts too; "Aufteilen"
  among the categories splits the transaction.
  """
  use AbakusWeb, :html

  alias Abakus.Ledger.Account
  alias AbakusWeb.{AccountGroups, TransactionForm}

  @main "main"

  @doc "Assigns the payee and category options for the params, from `payees` and `categories`."
  def assign_options(assigns) do
    transfers =
      for account <- transfer_options(assigns.params, assigns.accounts),
          do: %{label: TransactionForm.transfer_label(account), value: "a:#{account.id}"}

    payees =
      for payee <- assigns.payees,
          not payee.hidden,
          do: %{label: payee.name, value: "p:#{payee.name}"}

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

  @doc """
  The account a new entry goes to: the register's `account` while it takes entries, else the first of `accounts`
  that does in the sidebar's order; nil without one.
  """
  def entry_account_id(account, accounts) do
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

  @doc """
  The Konto select's options, grouped as in the sidebar: the accounts that take entries, and those of `kept` (ids)
  though they do not.
  """
  def account_options(accounts, kept) do
    for group <-
          accounts |> Map.values() |> Enum.filter(&offered_account?(&1, kept)) |> groups(),
        do: {group.label, Enum.map(group.rows, &{&1.account.name, &1.account.id})}
  end

  @doc "Whether the Konto select offers the account: one that takes entries, or one of `kept` (ids)."
  def offered_account?(account, kept), do: Account.takes_entries?(account) or account.id in kept

  @doc "Accounts as the sidebar groups them, without balances."
  def groups(accounts),
    do: accounts |> Enum.sort_by(&{&1.position, &1.id}) |> AccountGroups.build(%{})

  attr :prefix, :string, default: "tx"
  attr :params, :map, required: true
  attr :fixed, :boolean, default: false
  attr :target, :any, required: true
  attr :errors, :list, default: []
  attr :autofocus, :boolean, default: false

  attr :invalid, :map,
    default: nil,
    doc:
      "the refused amounts by side (`{typed, error}`); given, a field checks its amount as it is left"

  @doc "The amount as the phone sheet takes it: behind the transaction's sign, which a click turns round."
  def amount_field(assigns) do
    refused = refused(assigns.invalid, @main)

    assigns =
      assign(assigns,
        errors: assigns.errors ++ amount_errors(refused),
        key: assigns.invalid && @main,
        refused: refused
      )

    ~H"""
    <fieldset class="fieldset min-w-0">
      <label class="fieldset-legend" for={"#{@prefix}-amount"}>Betrag</label>
      <div class="join w-full">
        <.button
          id={"#{@prefix}-sign"}
          disabled={@fixed}
          class={["join-item app-sign", sign_class(@params["sign"])]}
          aria-label={sign_label(@params["sign"])}
          title={sign_label(@params["sign"])}
          phx-click="toggle_sign"
          phx-target={@target}
        >
          {if @params["sign"] == "+", do: "+", else: "−"}
        </.button>
        <label class={["input join-item w-full", @errors != [] && "input-error"]}>
          <.directed_amount
            id={"#{@prefix}-amount"}
            prefix={@prefix}
            name="transaction"
            side={@params}
            sign={@params["sign"]}
            disabled={@fixed}
            class="text-end tabular-nums app-tx-amount-input"
            errors={@errors}
            autofocus={@autofocus}
            key={@key}
            invalid={@refused}
            target={@target}
          />
          <span class="label">€</span>
        </label>
      </div>
      <.field_error id={"#{@prefix}-amount"} errors={@errors} />
    </fieldset>
    """
  end

  attr :prefix, :string, default: "tx"
  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :payee_options, :list, required: true
  attr :category_options, :list, required: true
  attr :payee_shown, :any, required: true, doc: "the parts whose payee field was asked for"
  attr :invalid, :map, default: nil, doc: "as for `amount_field/1`"
  attr :target, :any, required: true

  @doc """
  A split's parts as the phone sheet shows them: each with its payee (only where it differs from the transaction's,
  or once asked for), category, memo and amount in the transaction's direction, then "Teil hinzufügen" and what is
  left to split.
  """
  def parts(assigns) do
    assigns = assign(assigns, :subtransactions, TransactionForm.subtransactions(assigns.params))

    ~H"""
    <div class="flex flex-col gap-2 py-2">
      <div
        :for={{index, sub} <- @subtransactions}
        id={"#{@prefix}-sub-#{index}"}
        class="flex flex-col gap-2 rounded-box border border-base-content/10 p-3"
      >
        <div class="flex items-center gap-2">
          <div class="min-w-0 grow">
            <.payee_combo
              :if={own_payee?(@params, index, @payee_shown)}
              id={"#{@prefix}-sub-#{index}-payee"}
              prefix={@prefix}
              side={index}
              small
              params={@params}
              payee_options={@payee_options}
            />
            <.change_payee
              :if={!own_payee?(@params, index, @payee_shown)}
              prefix={@prefix}
              index={index}
              target={@target}
            />
          </div>
          <.remove_button prefix={@prefix} index={index} target={@target} />
        </div>
        <.category_cell
          id={"#{@prefix}-sub-#{index}-category"}
          prefix={@prefix}
          side={index}
          params={@params}
          accounts={@accounts}
          category_options={@category_options}
        />
        <div class="flex gap-2">
          <input
            id={"#{@prefix}-sub-#{index}-memo"}
            form={"#{@prefix}-form"}
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
              id={"#{@prefix}-sub-#{index}-amount"}
              prefix={@prefix}
              name={sub_name(index)}
              side={sub}
              sign={@params["sign"]}
              class="text-end tabular-nums"
              part
              errors={amount_errors(refused(@invalid, index))}
              key={@invalid && index}
              invalid={refused(@invalid, index)}
              target={@target}
            />
            <span class="label">€</span>
          </label>
        </div>
        <.field_error
          id={"#{@prefix}-sub-#{index}-amount"}
          errors={amount_errors(refused(@invalid, index))}
        />
      </div>
      <div class="flex items-center gap-2">
        <.add_button prefix={@prefix} target={@target} />
        <span id={"#{@prefix}-remainder"} class="ml-auto text-sm tabular-nums">
          <.remainder amount={directed_remainder(@params)} />
        </span>
      </div>
    </div>
    """
  end

  defp directed_remainder(params) do
    case TransactionForm.remainder(params) do
      nil -> nil
      left -> if params["sign"] == "+", do: left, else: -left
    end
  end

  # A part's amount goes into the transaction's column, so its minus counts against that direction as shown.
  attr :id, :string, required: true
  attr :prefix, :string, default: "tx"
  attr :name, :string, required: true
  attr :side, :map, required: true
  attr :sign, :string, required: true
  attr :class, :string, required: true
  attr :disabled, :boolean, default: false
  attr :part, :boolean, default: false
  attr :errors, :list, default: []
  attr :autofocus, :boolean, default: false

  attr :key, :string,
    default: nil,
    doc: "the side (\"main\" or a part's index) whose amount is checked on blur"

  attr :invalid, :any, default: nil, doc: "`{typed, error}` while the amount reads as none"
  attr :target, :any, default: nil

  defp directed_amount(assigns) do
    {column, other} =
      cond do
        not assigns.part -> {"amount", nil}
        assigns.sign == "+" -> {"inflow", "outflow"}
        true -> {"outflow", "inflow"}
      end

    assigns = assign(assigns, column: column, other: other)

    ~H"""
    <input
      :if={@other}
      type="hidden"
      form={"#{@prefix}-form"}
      name={"#{@name}[#{@other}]"}
      value=""
    />
    <input
      id={@id}
      form={"#{@prefix}-form"}
      name={"#{@name}[#{@column}]"}
      value={typed(@invalid) || TransactionForm.directed(@side, @sign)}
      class={@class}
      inputmode="text"
      autocapitalize="off"
      spellcheck="false"
      placeholder="0,00"
      aria-label="Betrag"
      aria-describedby={describedby("#{@prefix}-sign", @id, @errors)}
      aria-invalid={@errors != [] && "true"}
      autocomplete="off"
      phx-debounce="300"
      phx-blur={@key && "check_amount"}
      phx-value-side={@key}
      phx-target={@key && @target}
      disabled={@disabled}
      autofocus={@autofocus}
    />
    """
  end

  defp refused(nil, _side), do: nil
  defp refused(invalid, side), do: invalid[side]

  @doc "What was typed into an amount field that reads as none (`{typed, error}`), nil without."
  def typed({typed, _error}), do: typed
  def typed(nil), do: nil

  @doc "The error of an amount that reads as none, as the field's errors."
  def amount_errors({_typed, error}), do: [error]
  def amount_errors(nil), do: []

  @doc "An amount field's `aria-describedby`: its sign button, then its errors."
  def describedby(sign_id, id, errors),
    do: Enum.join([sign_id | List.wrap(field_describedby(id, errors, nil))], " ")

  attr :prefix, :string, default: "tx"
  attr :index, :string, required: true
  attr :target, :any, required: true

  def remove_button(assigns) do
    ~H"""
    <.button
      id={"#{@prefix}-sub-#{@index}-remove"}
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

  attr :prefix, :string, default: "tx"
  attr :index, :string, required: true
  attr :target, :any, required: true

  def change_payee(assigns) do
    ~H"""
    <.button
      id={"#{@prefix}-sub-#{@index}-change-payee"}
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

  @doc "Whether a part has a payee field of its own: where it differs from the transaction's, or once asked for."
  def own_payee?(params, index, shown) do
    part = TransactionForm.side(params, index)

    index in shown or TransactionForm.transfer?(part) or
      part["payee"] not in [nil, "", params["payee"]]
  end

  attr :prefix, :string, default: "tx"
  attr :target, :any, required: true

  def add_button(assigns) do
    ~H"""
    <.button
      id={"#{@prefix}-add-sub"}
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

  attr :id, :string, required: true
  attr :prefix, :string, default: "tx"
  attr :side, :string, required: true
  attr :params, :map, required: true
  attr :payee_options, :list, required: true
  attr :fixed, :boolean, default: false
  attr :label, :boolean, default: false
  attr :small, :boolean, default: false
  attr :errors, :list, default: []

  def payee_combo(assigns) do
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
      options_from={"#{@prefix}-payee-list"}
      placeholder="Empfänger"
      allow_create
      create_label="Empfänger „%{text}“ anlegen"
      create_field={@created}
      class={@small && "input-sm"}
      form={"#{@prefix}-form"}
      disabled={@fixed}
      errors={@errors}
    />
    """
  end

  attr :id, :string, required: true
  attr :prefix, :string, default: "tx"
  attr :side, :string, required: true
  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :category_options, :list, required: true
  attr :fixed, :boolean, default: false
  attr :label, :boolean, default: false
  attr :small, :boolean, default: false
  attr :errors, :list, default: []

  def category_cell(assigns) do
    side = TransactionForm.side(assigns.params, assigns.side)
    main? = assigns.side == @main

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
          options_from={
            if @splittable?,
              do: "#{@prefix}-category-split-list",
              else: "#{@prefix}-category-list"
          }
          placeholder="Kategorie"
          class={@small && "input-sm"}
          form={"#{@prefix}-form"}
          errors={@errors}
        />
    <% end %>
    """
  end

  defp none_placeholder(side) do
    if TransactionForm.transfer?(side), do: "Keine Kategorie nötig", else: ""
  end

  attr :prefix, :string, default: "tx"
  attr :payee_options, :list, required: true
  attr :category_options, :list, required: true

  @doc "The option lists every side's comboboxes share; \"Aufteilen\" only for the transaction's own category."
  def option_lists(assigns) do
    ~H"""
    <.combobox_options id={"#{@prefix}-payee-list"} options={@payee_options} />
    <.combobox_options
      :for={
        {id, options} <- [
          {"#{@prefix}-category-list", @category_options},
          {"#{@prefix}-category-split-list",
           @category_options ++ [%{label: "Aufteilen", value: "split"}]}
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

  @doc "The params name of a side: \"main\" is the transaction, an index a part."
  def side_name(@main), do: "transaction"
  def side_name(index), do: sub_name(index)

  def sub_name(index), do: "transaction[subtransactions][#{index}]"
  def sub_name(index, field), do: "#{sub_name(index)}[#{field}]"

  def sign_label("+"), do: "Eingang, umschalten auf Ausgang"
  def sign_label(_sign), do: "Ausgang, umschalten auf Eingang"

  defp sign_class("+"), do: "text-success-ink"
  defp sign_class(_sign), do: "text-error-ink"
end

defmodule Abakus.Depot.Portfolios.TransactionForm do
  @moduledoc """
  A purchase, sale, dividend, deposit or removal as the user enters it, in euros: the checks a
  transaction must pass and the transactions it books (ADR 0013).

  The amount follows shares × price (a dividend's gross value) with fees and taxes until the user
  overwrites it (`amount_set`); `expected_amount` then holds what they give when the amount differs
  by more than a four-decimal price explains. A purchase or sale without an account is an inbound
  or outbound delivery. The price is only an input aid and is not stored.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Abakus.Depot.DecimalInput
  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.Depot.Receipts.Fields
  alias Abakus.LocalTime
  alias Abakus.Money

  @kinds [:purchase, :sale, :dividend, :deposit, :removal]

  @primary_key false
  embedded_schema do
    field :kind, Ecto.Enum, values: @kinds, default: :purchase
    field :portfolio_id, :integer
    field :date, :date
    field :security_id, :integer
    field :shares, DecimalInput
    field :price, DecimalInput
    field :gross, DecimalInput
    field :fees, DecimalInput, default: Decimal.new(0)
    field :taxes, DecimalInput, default: Decimal.new(0)
    field :amount, DecimalInput
    field :amount_set, :boolean, default: false
    field :account_id, :integer
    field :remove_at_once, :boolean, default: false
    field :expected_amount, :decimal
  end

  @fields [
    :kind,
    :portfolio_id,
    :date,
    :security_id,
    :shares,
    :price,
    :gross,
    :fees,
    :taxes,
    :amount,
    :amount_set,
    :account_id,
    :remove_at_once
  ]

  # A price rounded to four decimal places is off by at most this much per share.
  @price_rounding Decimal.new("0.00005")
  @cent_rounding Decimal.new("0.005")
  @limit 1_000_000_000

  def kinds, do: @kinds

  @doc """
  Casts and checks `attrs`. `choices` holds the `portfolio_ids`, `account_ids` and
  `security_ids` the user may book on, as sets, and `held_shares`, a function of portfolio id,
  security id and date that gives the fewest shares × 10⁸ held from the end of that day on.
  """
  def changeset(%__MODULE__{} = form, attrs, choices) do
    form
    |> cast(attrs, @fields)
    |> zero_when_blank([:fees, :taxes])
    |> validate_required([:kind, :date])
    |> validate_kind()
    |> validate_not_in_future()
    |> validate_choice(:portfolio_id, choices.portfolio_ids)
    |> validate_choice(:account_id, choices.account_ids)
    |> validate_choice(:security_id, choices.security_ids)
    |> validate_number(:fees, greater_than_or_equal_to: 0)
    |> validate_number(:taxes, greater_than_or_equal_to: 0)
    |> validate_places([:fees, :taxes, :gross, :amount], 2)
    |> validate_places([:shares], 8)
    |> validate_below_limit([:shares, :price, :gross, :fees, :taxes])
    |> put_amount()
    |> validate_required([:amount])
    |> validate_number(:amount, greater_than: 0)
    |> validate_below_limit([:amount])
    |> put_expected_amount()
    |> validate_holding(choices.held_shares)
  end

  defp zero_when_blank(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      if get_field(changeset, field),
        do: changeset,
        else: put_change(changeset, field, Decimal.new(0))
    end)
  end

  defp validate_kind(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in [:purchase, :sale] ->
        changeset
        |> validate_required([:portfolio_id, :security_id, :shares, :price])
        |> validate_number(:shares, greater_than: 0)
        |> validate_number(:price, greater_than: 0)

      :dividend ->
        changeset
        |> validate_required([:security_id, :gross, :account_id])
        |> validate_number(:shares, greater_than: 0)
        |> validate_number(:gross, greater_than: 0)

      _deposit_or_removal ->
        validate_required(changeset, [:account_id])
    end
  end

  defp validate_not_in_future(changeset) do
    date = get_field(changeset, :date)

    if date && Date.after?(date, LocalTime.today()),
      do: add_error(changeset, :date, "darf nicht in der Zukunft liegen"),
      else: changeset
  end

  defp validate_choice(changeset, field, ids) do
    validate_change(changeset, field, fn ^field, id ->
      if MapSet.member?(ids, id), do: [], else: [{field, "ist ungültig"}]
    end)
  end

  defp validate_below_limit(changeset, fields) do
    Enum.reduce(fields, changeset, &validate_number(&2, &1, less_than: @limit))
  end

  defp validate_places(changeset, fields, places) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      validate_change(changeset, field, &places_error(&1, &2, places))
    end)
  end

  defp places_error(field, value, places) do
    if Decimal.equal?(value, Decimal.round(value, places)),
      do: [],
      else: [{field, "hat höchstens #{places} Nachkommastellen"}]
  end

  # Until the user overwrites it, the amount follows the other fields; a deposit's or removal's is
  # entered.
  defp put_amount(changeset) do
    entered? =
      get_field(changeset, :kind) in [:deposit, :removal] or
        (get_field(changeset, :amount_set) and get_field(changeset, :amount) != nil)

    if entered?,
      do: changeset,
      else: put_change(changeset, :amount, computed_amount(changeset) |> round_cents())
  end

  defp put_expected_amount(changeset) do
    amount = get_field(changeset, :amount)
    computed = computed_amount(changeset)

    if amount && computed &&
         Decimal.gt?(Decimal.abs(Decimal.sub(amount, computed)), tolerance(changeset)),
       do: put_change(changeset, :expected_amount, round_cents(computed)),
       else: put_change(changeset, :expected_amount, nil)
  end

  # The exact amount the other fields give, nil while one of them is missing.
  defp computed_amount(changeset) do
    fees_and_taxes = Decimal.add(get_field(changeset, :fees), get_field(changeset, :taxes))

    case {get_field(changeset, :kind), gross(changeset)} do
      {_kind, nil} -> nil
      {:purchase, gross} -> Decimal.add(gross, fees_and_taxes)
      {_sale_or_dividend, gross} -> Decimal.sub(gross, fees_and_taxes)
    end
  end

  defp gross(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in [:purchase, :sale] ->
        shares = get_field(changeset, :shares)
        price = get_field(changeset, :price)
        shares && price && Decimal.mult(shares, price)

      :dividend ->
        get_field(changeset, :gross)

      _deposit_or_removal ->
        nil
    end
  end

  defp tolerance(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in [:purchase, :sale] -> price_tolerance(get_field(changeset, :shares))
      _dividend -> @cent_rounding
    end
  end

  @doc """
  How far an amount may lie from `shares` × a price with four decimal places, fees and taxes:
  half a cent plus the price's rounding for every share.
  """
  def price_tolerance(shares),
    do: Decimal.add(@cent_rounding, Decimal.mult(shares, @price_rounding))

  defp round_cents(nil), do: nil
  defp round_cents(decimal), do: Decimal.round(decimal, 2, :half_up)

  # No sale or outbound delivery beyond the shares held on its day or later.
  defp validate_holding(changeset, held_shares) do
    with :sale <- get_field(changeset, :kind),
         [] <- changeset.errors,
         held =
           held_shares.(
             fetch!(changeset, :portfolio_id),
             fetch!(changeset, :security_id),
             fetch!(changeset, :date)
           ),
         true <- shares(fetch!(changeset, :shares)) > held do
      add_error(changeset, :shares, "übersteigt den Bestand von %{held} Stück",
        held: format_shares(held)
      )
    else
      _fine -> changeset
    end
  end

  defp fetch!(changeset, field), do: fetch_field!(changeset, field)

  defp format_shares(shares) do
    shares
    |> Decimal.div(100_000_000)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> String.replace(".", ",")
  end

  @doc """
  The params that show `transaction`, one `Transaction.editable?/1`, in the form, as
  `Abakus.Money.number/2` writes them. The price comes from gross value and shares; the amount counts as overwritten when
  that price, rounded to four places, gives another one.
  """
  def params_of(%Transaction{} = transaction) do
    kind = kind_of(transaction.type)
    fees = unit_sum(transaction, :fee)
    taxes = unit_sum(transaction, :tax)
    amount = Decimal.div(transaction.amount, 100)
    shares = transaction.shares && Decimal.div(transaction.shares, 100_000_000)

    %{
      "kind" => to_string(kind),
      "date" => transaction.date_time |> NaiveDateTime.to_date() |> Date.to_iso8601(),
      "portfolio_id" => id_param(transaction.portfolio_id),
      "account_id" => id_param(transaction.account_id),
      "security_id" => id_param(transaction.security_id),
      "shares" => typed(shares),
      "fees" => typed(fees, 2),
      "taxes" => typed(taxes, 2),
      "amount" => typed(amount, 2),
      "amount_set" => "false"
    }
    |> Map.merge(entered_values(kind, shares, amount, fees, taxes))
  end

  @doc """
  The params that show what the model recognised on a receipt, see `Abakus.Depot.Receipts.Fields`,
  without portfolio, account and security. The receipt's amount counts as overwritten, so that
  the form shows where the other fields give another one; a dividend's gross value is what the
  account is credited with fees and taxes.
  """
  def params_of_receipt(%Fields{} = fields) do
    fees = fields.fees || Decimal.new(0)
    taxes = fields.taxes || Decimal.new(0)

    %{
      "kind" => to_string(fields.kind),
      "date" => fields.date && Date.to_iso8601(fields.date),
      "shares" => typed(fields.shares),
      "fees" => typed(fees, 2),
      "taxes" => typed(taxes, 2),
      "amount" => typed(fields.amount, 2),
      "amount_set" => to_string(fields.amount != nil)
    }
    |> Map.merge(recognised_values(fields, fees, taxes))
  end

  defp recognised_values(%Fields{kind: :dividend, amount: nil} = fields, _fees, _taxes),
    do: %{
      "gross" =>
        fields.shares && fields.price &&
          fields.shares |> Decimal.mult(fields.price) |> round_cents() |> typed(2)
    }

  defp recognised_values(%Fields{kind: :dividend} = fields, fees, taxes),
    do: %{"gross" => fields.amount |> Decimal.add(fees) |> Decimal.add(taxes) |> typed(2)}

  defp recognised_values(fields, _fees, _taxes), do: %{"price" => typed(fields.price, 2)}

  defp kind_of(type) when type in [:buy, :inbound_delivery], do: :purchase
  defp kind_of(type) when type in [:sell, :outbound_delivery], do: :sale
  defp kind_of(type) when type in [:dividend, :deposit, :removal], do: type

  defp unit_sum(transaction, type) do
    transaction.units
    |> Enum.filter(&(&1.type == type))
    |> Enum.sum_by(& &1.amount)
    |> Decimal.div(100)
  end

  defp entered_values(:dividend, _shares, amount, fees, taxes),
    do: %{"gross" => amount |> Decimal.add(fees) |> Decimal.add(taxes) |> typed(2)}

  defp entered_values(kind, shares, amount, fees, taxes) when kind in [:purchase, :sale] do
    fees_and_taxes = Decimal.add(fees, taxes)

    {gross, computed} =
      if kind == :purchase,
        do: {Decimal.sub(amount, fees_and_taxes), &Decimal.add(&1, fees_and_taxes)},
        else: {Decimal.add(amount, fees_and_taxes), &Decimal.sub(&1, fees_and_taxes)}

    price = gross |> Decimal.div(shares) |> Decimal.round(4)
    computed_amount = shares |> Decimal.mult(price) |> computed.() |> round_cents()

    %{
      "price" => typed(price, 2),
      "amount_set" => to_string(not Decimal.equal?(computed_amount, amount))
    }
  end

  defp entered_values(_deposit_or_removal, _shares, _amount, _fees, _taxes), do: %{}

  defp id_param(nil), do: ""
  defp id_param(id), do: to_string(id)

  defp typed(decimal, places \\ 0)
  defp typed(nil, _places), do: ""
  defp typed(decimal, places), do: Money.number(decimal, places)

  @doc """
  The attributes of the transactions a valid form books, without user and receipt: one, or for
  a dividend removed at once a second, independent removal of its amount.
  """
  def to_transactions(%__MODULE__{} = form) do
    transaction = transaction(form)

    if form.kind == :dividend and form.remove_at_once,
      do: [transaction, removal_of(transaction)],
      else: [transaction]
  end

  defp transaction(form) do
    %{
      type: type(form.kind, form.account_id),
      date_time: NaiveDateTime.new!(form.date, ~T[00:00:00]),
      portfolio_id: if(form.kind in [:purchase, :sale], do: form.portfolio_id),
      account_id: form.account_id,
      security_id: if(form.kind in [:purchase, :sale, :dividend], do: form.security_id),
      shares: stored_shares(form),
      amount: cents(form.amount),
      currency: "EUR",
      source: :manual,
      units: units(form)
    }
  end

  defp stored_shares(%__MODULE__{kind: kind, shares: %Decimal{} = shares})
       when kind in [:purchase, :sale, :dividend],
       do: shares(shares)

  defp stored_shares(_form), do: nil

  defp type(:purchase, nil), do: :inbound_delivery
  defp type(:purchase, _account_id), do: :buy
  defp type(:sale, nil), do: :outbound_delivery
  defp type(:sale, _account_id), do: :sell
  defp type(kind, _account_id), do: kind

  defp units(%__MODULE__{kind: kind}) when kind in [:deposit, :removal], do: []

  defp units(form) do
    for {type, value} <- [fee: form.fees, tax: form.taxes], Decimal.positive?(value) do
      %{type: type, amount: cents(value), currency: "EUR"}
    end
  end

  defp removal_of(dividend) do
    %{dividend | type: :removal, security_id: nil, shares: nil, units: []}
  end

  defp shares(decimal), do: decimal |> Decimal.mult(100_000_000) |> Decimal.to_integer()
  defp cents(decimal), do: decimal |> Decimal.mult(100) |> Decimal.to_integer()
end

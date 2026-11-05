defmodule Abakus.Depot.Securities.Security do
  @moduledoc """
  A security, shared by all users. `quote_feed` and `symbol` say where prices come from.
  `latest_*` is the latest quote, `fetched_at` and `fetch_error` the last successful and the last
  failed fetch, `checked_at` the last attempt; `divvy_diary_error` why DivvyDiary last delivered
  nothing for its ISIN, `divvy_diary_unknown` that DivvyDiary does not know it.
  """
  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Depot.Securities.ISIN

  schema "depot_securities" do
    field :name, :string
    field :isin, :string
    field :wkn, :string
    field :currency, :string
    field :note, :string
    field :retired, :boolean, default: false
    field :attributes, :map, default: %{}
    field :quote_feed, Ecto.Enum, values: [:yahoo, :manual], default: :manual
    field :symbol, :string
    field :latest_date, :date
    field :latest_close, :integer
    field :latest_at, :utc_datetime_usec
    field :fetched_at, :utc_datetime_usec
    field :checked_at, :utc_datetime_usec
    field :fetch_error, :string
    field :divvy_diary_error, :string
    field :divvy_diary_unknown, :boolean, default: false

    timestamps()
  end

  @ter "ter"
  @fund_size "aum"

  @doc "The TER from its attribute as a fraction, e.g. 0.002 for 0.20 %; nil without one."
  def ter(%__MODULE__{attributes: %{@ter => ter}}) when is_float(ter), do: Decimal.from_float(ter)
  def ter(%__MODULE__{attributes: %{@ter => ter}}) when is_integer(ter), do: Decimal.new(ter)
  def ter(%__MODULE__{}), do: nil

  @doc """
  The fund size from its attribute in cents, a plain amount without a currency; nil without one.
  """
  def fund_size(%__MODULE__{attributes: %{@fund_size => size}}) when is_integer(size), do: size
  def fund_size(%__MODULE__{}), do: nil

  @doc "Sets the TER and the fund size given, in the units above; nil keeps the stored one."
  def ter_and_fund_size_changeset(%__MODULE__{} = security, ter, fund_size) do
    attributes =
      (security.attributes || %{})
      |> put_known(@ter, ter)
      |> put_known(@fund_size, fund_size)

    change(security, attributes: attributes)
  end

  @doc "Removes the TER and the fund size."
  def without_ter_and_fund_size_changeset(%__MODULE__{} = security),
    do: change(security, attributes: Map.drop(security.attributes || %{}, [@ter, @fund_size]))

  defp put_known(attributes, _key, nil), do: attributes
  defp put_known(attributes, key, value), do: Map.put(attributes, key, value)

  @doc """
  The attributes set on the security other than TER and fund size as `{type, value}`, in the
  order of `types`, the attribute types of securities; a value without its type is left out.
  """
  def attributes(%__MODULE__{attributes: attributes}, types) do
    attributes = attributes || %{}

    for %{key: key} = type <- types,
        key not in [@ter, @fund_size],
        attributes[key] not in [nil, ""],
        do: {type, attributes[key]}
  end

  @doc "Changes where prices come from, the ISIN and whether it is retired; a blank ISIN removes it."
  def changeset(security, attrs) do
    security
    |> cast(attrs, [:quote_feed, :symbol, :isin, :retired])
    |> update_change(:symbol, &(&1 && String.trim(&1)))
    |> validate_required([:quote_feed])
    |> then(fn cs ->
      if get_field(cs, :quote_feed) == :yahoo, do: validate_required(cs, [:symbol]), else: cs
    end)
    |> normalize_isin()
  end

  @doc """
  A security the user creates by its ISIN, with its name and, for prices from Yahoo, its symbol;
  without a symbol its prices are entered by hand.
  """
  def create_changeset(security, attrs) do
    security
    |> cast(attrs, [:isin, :name, :symbol])
    |> normalize_isin()
    |> update_change(:name, &String.trim/1)
    |> update_change(:symbol, &String.trim/1)
    |> validate_required([:isin, :name])
    |> then(&put_change(&1, :quote_feed, if(get_field(&1, :symbol), do: :yahoo, else: :manual)))
    |> put_change(:currency, "EUR")
  end

  defp normalize_isin(changeset) do
    changeset
    |> update_change(:isin, &(&1 && &1 |> String.replace(" ", "") |> String.upcase()))
    |> validate_change(:isin, fn :isin, isin ->
      if ISIN.valid?(isin), do: [], else: [isin: "ist keine gültige ISIN."]
    end)
  end
end

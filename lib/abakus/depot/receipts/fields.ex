defmodule Abakus.Depot.Receipts.Fields do
  @moduledoc """
  What the model recognised on a receipt, and the JSON schema it answers with. A purchase, sale
  or dividend is booked from it; any other receipt is of kind `:other`. Amounts are in the
  receipt's currency, `price` per share (a dividend's per share), `amount` what the account is
  charged or credited. Numbers are magnitudes, the kind tells the direction, as banks print a
  charge with a minus or without.

  The model copies numbers as the receipt prints them, as „8,261“ or „1.691,55“, and they are
  read here: a small model misreads 8,261 shares as 8261 when it converts them itself. Chat
  APIs such as LM Studio or Ollama only constrain the answer by the schema and never show the
  model its descriptions, so the instructions say what each field holds.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Abakus.Depot.Receipts.Fields.OrderedObject

  @kinds [:purchase, :sale, :dividend, :other]
  @texts [:isin, :security_name, :depot_number, :bank_reference]
  @numbers [:shares, :price, :fees, :taxes, :amount]

  @primary_key false
  embedded_schema do
    field :kind, Ecto.Enum, values: @kinds
    field :date, :date
    field :isin, :string
    field :security_name, :string
    field :shares, :decimal
    field :price, :decimal
    field :fees, :decimal
    field :taxes, :decimal
    field :amount, :decimal
    field :depot_number, :string
    field :bank_reference, :string
  end

  # In the order the model answers: shares, price, fees and taxes before the amount they add up to.
  @descriptions [
    kind: "purchase, sale or dividend; other for any other receipt",
    date: "the trade or payment date, YYYY-MM-DD",
    isin: "the security's ISIN",
    security_name: "the security's name",
    shares: "number of shares (Stück, Nominale), as printed, such as 8,261",
    price:
      "price per share (Ausführungskurs, Kurs), not the total (Kurswert); " <>
        "for a dividend the dividend per share",
    fees:
      "sum of fees, commissions and charges (Provision, Orderentgelt, Börsengebühr, " <>
        "fremde Spesen), without taxes",
    taxes:
      "sum of taxes withheld, such as Kapitalertragsteuer, Solidaritätszuschlag, Kirchensteuer " <>
        "or Quellensteuer; 0 when they come on a separate tax notice",
    amount:
      "the final amount charged to or credited to the account, after fees and taxes " <>
        "(Ausmachender Betrag, Endbetrag, nach Steuern); the amount before taxes only " <>
        "where the receipt states no amount after taxes, as a dividend whose taxes come " <>
        "on a separate tax notice",
    depot_number: "the securities account (Depot) number",
    bank_reference: "the bank's reference or order number of this receipt"
  ]

  @doc """
  The JSON schema of the model's answer: every field, null where the receipt has none, its
  properties an `OrderedObject` in the order the model answers them.
  """
  def json_schema do
    properties =
      for {name, description} <- @descriptions,
          do: {name, Map.put(type_of(name), :description, description)}

    %{
      type: "object",
      additionalProperties: false,
      required: Keyword.keys(@descriptions),
      properties: %OrderedObject{pairs: properties}
    }
  end

  defp type_of(:kind), do: %{type: "string", enum: Enum.map(@kinds, &Atom.to_string/1)}
  defp type_of(_number_or_text), do: %{type: ["string", "null"]}

  @doc """
  The fields of the model's answer, a JSON object by `json_schema/0`; `:error` for one that is
  no such object, misses a field or has one of the wrong type. A number may be a JSON number or
  text as a receipt prints it, in its `notation` (see `notation/1`), with a currency or sign
  around; text without a digit is no number.
  """
  def from_answer(answer, notation \\ :english) when is_binary(answer) do
    with {:ok, %{} = json} <- JSON.decode(answer),
         true <- Enum.all?(Keyword.keys(@descriptions), &Map.has_key?(json, Atom.to_string(&1))),
         true <-
           Enum.all?(
             @texts,
             &(is_binary(json[Atom.to_string(&1)]) or is_nil(json[Atom.to_string(&1)]))
           ),
         {:ok, fields} <- json |> changeset(notation) |> apply_action(:insert) do
      {:ok, fields}
    else
      _invalid -> :error
    end
  end

  defp changeset(json, notation) do
    json = json |> Map.update("date", nil, &iso_date/1) |> unsigned(notation)

    %__MODULE__{}
    |> cast(json, [:kind, :date | @texts ++ @numbers], empty_values: [nil, ""])
    |> validate_required([:kind])
    |> update_change(:isin, &(&1 |> String.replace(~r/\s/, "") |> String.upcase()))
  end

  # A German date such as 16.03.2026, as models answer now and then despite the schema.
  defp iso_date(date) when is_binary(date) do
    case Regex.run(~r/^\s*(\d{1,2})\.(\d{1,2})\.(\d{4})\s*$/, date) do
      [_date, day, month, year] -> "#{year}-#{zero_pad(month)}-#{zero_pad(day)}"
      nil -> date
    end
  end

  defp iso_date(date), do: date

  defp zero_pad(number), do: String.pad_leading(number, 2, "0")

  @doc """
  How the receipt's `text` writes numbers: `:german` with a decimal comma, as in 1.691,55,
  `:english` with a decimal point; by the amounts with two decimal places it has more of.
  """
  def notation(text) do
    german = length(Regex.scan(~r/(?<![\d.,])\d+(?:\.\d{3})*,\d{2}(?![\d.,])/, text))
    english = length(Regex.scan(~r/(?<![\d.,])\d+(?:,\d{3})*\.\d{2}(?![\d.,])/, text))
    if english > german, do: :english, else: :german
  end

  # A bank prints a charge as -879.28 or 879.28-.
  defp unsigned(json, notation) do
    Enum.reduce(@numbers, json, fn name, json ->
      Map.update(json, Atom.to_string(name), nil, &magnitude(&1, notation))
    end)
  end

  defp magnitude(number, _notation) when is_number(number), do: abs(number)

  defp magnitude(number, notation) when is_binary(number) do
    blankless = String.replace(number, ~r/(?<=[\d.,])\s+(?=[\d.,])/u, "")

    case Regex.run(~r/\d(?:[\d.,]*\d)?/, blankless) do
      [digits] -> decimal(digits, notation)
      nil -> nil
    end
  end

  defp magnitude(other, _notation), do: other

  # The last of two separators is decimal; a lone one before three digits follows the notation (1.200 vs 1.2).
  defp decimal(digits, notation) do
    separators = for <<char <- digits>>, char in [?., ?,], uniq: true, do: char

    decimal_separator =
      case separators do
        [] -> nil
        [_thousands, decimal] -> decimal
        [separator] -> lone(digits, separator, notation)
      end

    {whole, fraction} =
      case decimal_separator && String.split(digits, <<decimal_separator>>) do
        nil -> {digits, ""}
        parts -> {Enum.join(Enum.drop(parts, -1)), List.last(parts)}
      end

    String.replace(whole, ~r/[.,]/, "") <> if(fraction == "", do: "", else: "." <> fraction)
  end

  defp lone(digits, separator, notation) do
    groups = String.split(digits, <<separator>>)
    thousands = if notation == :german, do: ?., else: ?,

    cond do
      length(groups) > 2 -> nil
      String.length(List.last(groups)) != 3 -> separator
      separator == thousands -> nil
      true -> separator
    end
  end
end

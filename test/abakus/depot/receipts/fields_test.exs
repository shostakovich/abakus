defmodule Abakus.Depot.Receipts.FieldsTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.ReceiptsFixtures

  alias Abakus.Depot.Receipts.Fields

  test "the schema asks for every field, nullable but the kind, numbers as text" do
    schema = Fields.json_schema()
    properties = Map.new(schema.properties.pairs)

    assert schema.additionalProperties == false
    assert schema.required == Keyword.keys(schema.properties.pairs)
    assert properties.kind.enum == ~w(purchase sale dividend other)
    assert properties.shares.type == ["string", "null"]
    assert properties.isin.type == ["string", "null"]
  end

  test "the schema has its properties in the order the model answers, amount after its parts" do
    order = Keyword.keys(Fields.json_schema().properties.pairs)

    assert Enum.take(order, 3) == [:kind, :date, :isin]
    assert Enum.find_index(order, &(&1 == :amount)) > Enum.find_index(order, &(&1 == :taxes))

    encoded = JSON.encode!(Fields.json_schema())
    {:ok, json} = JSON.decode(encoded)
    positions = for name <- order, do: :binary.match(encoded, ~s("#{name}":{)) |> elem(0)

    assert positions == Enum.sort(positions)
    assert Map.keys(json["properties"]) |> Enum.sort() == Enum.sort(json["required"])
  end

  test "reads numbers as the receipt prints them, in its notation" do
    read = fn number, notation ->
      {:ok, fields} = Fields.from_answer(answer(%{"shares" => number}), notation)
      fields.shares && Decimal.to_string(Decimal.normalize(fields.shares), :normal)
    end

    assert read.("8,261", :german) == "8.261"
    assert read.("STK 4,000", :german) == "4"
    assert read.("1.200", :german) == "1200"
    assert read.("1.691,55", :german) == "1691.55"
    assert read.("EUR 2.193,43-", :german) == "2193.43"
    assert read.("1 . 0 0 0, 5", :german) == "1000.5"
    assert read.("0.57", :german) == "0.57"
    assert read.("108,225", :german) == "108.225"
    assert read.("1.234.567", :german) == "1234567"

    assert read.("1,200", :english) == "1200"
    assert read.("1.200", :english) == "1.2"
    assert read.("1,691.55 EUR", :english) == "1691.55"
    assert read.("4.000", :english) == "4"

    assert read.("7", :german) == "7"
    assert read.(">—, ", :german) == nil
    assert read.("", :german) == nil
  end

  test "notation/1 tells a decimal comma from a decimal point by the amounts" do
    assert Fields.notation("Kurswert 1.685,10 EUR\nProvision 4,95 EUR\nam 16.03.2026") == :german
    assert Fields.notation("Credit 0.57 EUR 17 9.69 EUR\nTaxes -2.55 EUR") == :english
    assert Fields.notation("Total 1,125.00 EUR\nFees 1,00 EUR\nTaxes 2.50 EUR") == :english
    assert Fields.notation("Datum 15.12.2008, Seite 1") == :german
  end

  test "reads an answer by the schema, numbers as JSON numbers or strings" do
    assert {:ok, %Fields{kind: :purchase, date: ~D[2026-10-01], fees: fees, taxes: nil} = fields} =
             Fields.from_answer(answer(%{"price" => "12.0699", "isin" => " ie00 bk5bqt80"}))

    assert Decimal.equal?(fees, 0)
    assert Decimal.equal?(fields.price, "12.0699")
    assert fields.isin == "IE00BK5BQT80"
  end

  test "takes numbers as magnitudes, however the bank signs a charge" do
    assert {:ok, fields} =
             Fields.from_answer(
               answer(%{
                 "amount" => -879.28,
                 "fees" => "10.00-",
                 "taxes" => "-1.5",
                 "price" => 29.975
               })
             )

    assert Decimal.equal?(fields.amount, "879.28")
    assert Decimal.equal?(fields.fees, "10.00")
    assert Decimal.equal?(fields.taxes, "1.5")
    assert Decimal.equal?(fields.price, "29.975")
  end

  test "reads a German date" do
    assert {:ok, %Fields{date: ~D[2026-03-16]}} =
             Fields.from_answer(answer(%{"date" => "16.03.2026"}))

    assert {:ok, %Fields{date: ~D[2026-03-06]}} =
             Fields.from_answer(answer(%{"date" => "6.3.2026"}))
  end

  test "refuses an answer off the schema" do
    assert Fields.from_answer(~s({"kind": "purchase"})) == :error
    assert Fields.from_answer(answer(%{"kind" => nil})) == :error
    assert Fields.from_answer(answer(%{"date" => "Oktober 2026"})) == :error
    assert Fields.from_answer(answer(%{"bank_reference" => 1})) == :error
    assert Fields.from_answer("```json\n{}\n```") == :error
  end
end

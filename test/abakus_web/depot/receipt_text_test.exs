defmodule AbakusWeb.Depot.ReceiptTextTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.ReceiptsFixtures

  alias Abakus.Depot.Receipts.Fields
  alias AbakusWeb.Depot.ReceiptText

  defp marks(text, fields) do
    for {:mark, mark} <- ReceiptText.pieces(text, fields), do: mark
  end

  test "marks the recognised values where the text has them" do
    {:ok, fields} = Fields.from_answer(answer())

    assert marks(receipt_text(), fields) == [
             "4472",
             "01.10.2026",
             "IE00BK5BQT80",
             "93,207",
             "12,0699",
             "1.125,00",
             "1.125,00",
             "SP-0001"
           ]
  end

  test "keeps the whole text in its pieces" do
    {:ok, fields} = Fields.from_answer(answer())

    assert receipt_text() |> ReceiptText.pieces(fields) |> Enum.map_join(&elem(&1, 1)) ==
             receipt_text()
  end

  test "marks no part of a longer number or word" do
    fields = %Fields{shares: Decimal.new("10"), depot_number: "44"}

    assert marks("am 01.10.2026 · 10 Stück · Depot 4472 · 10,5 · 1.210 · 44", fields) == [
             "10",
             "44"
           ]
  end

  test "marks no lone digit" do
    fields = %Fields{fees: Decimal.new("1")}

    assert marks("Seite 1/1 · Provision 1,00 EUR", fields) == ["1,00"]
  end

  test "marks a lone digit only as shares beside „Stück“" do
    fields = %Fields{shares: Decimal.new("5")}

    assert ReceiptText.pieces("Seite 5 · Stück 5", fields) == [
             {:text, "Seite 5 · Stück "},
             {:mark, "5"}
           ]
  end

  test "an unrecognised receipt is text alone, one without text nothing" do
    assert ReceiptText.pieces("Beleg", nil) == [{:text, "Beleg"}]
    assert ReceiptText.pieces(nil, %Fields{}) == []
  end
end

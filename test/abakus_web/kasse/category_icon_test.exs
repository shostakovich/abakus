defmodule AbakusWeb.Kasse.CategoryIconTest do
  use ExUnit.Case, async: true

  alias Abakus.Kasse.Categories.Category
  alias Abakus.Kasse.Expenses.Expense
  alias AbakusWeb.Kasse.CategoryIcon

  for {name, plush} <- [
        {"Lebensmittel", "shopping-cart"},
        {"Restaurant", "utensils"},
        {"Haushalt", "house"},
        {"Miete & Nebenkosten", "key"},
        {"Nebenkosten", "zap"},
        {"Transport", "car"},
        {"ÖPNV", "car"},
        {"Reisen", "plane"},
        {"Freizeit", "ticket"},
        {"Gesundheit", "heart"},
        {"Geschenke", "gift"},
        {"Kleidung", "shirt"},
        {"Kita", "baby"},
        {"Haustier", "paw-print"},
        {"Bücher", "graduation-cap"},
        {"Streaming-Abos", "smartphone"},
        {"Versicherungen", "shield"},
        {"Sonstiges", "receipt"},
        {"Kunst", "tag"},
        {nil, "tag"}
      ] do
    test "#{inspect(name)} shows #{plush}" do
      assert CategoryIcon.for_category(unquote(name)) == unquote(plush)
      assert unquote(plush) in AbakusWeb.Plush.names()
    end
  end

  test "an expense shows its category, a reimbursement banknotes" do
    assert CategoryIcon.for_expense(%Expense{category: %Category{name: "Reisen"}}) == "plane"
    assert CategoryIcon.for_expense(%Expense{category: nil}) == "tag"
    assert CategoryIcon.for_expense(%Expense{reimbursement: true, category: nil}) == "banknote"
  end
end

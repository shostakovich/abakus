defmodule Abakus.Ledger.PayeeRenameConditionTest do
  use ExUnit.Case, async: true

  alias Abakus.Ledger.PayeeRenameCondition

  defp condition(operator, text), do: %PayeeRenameCondition{operator: operator, text: text}

  describe "matches?/2" do
    test "each operator ignores case" do
      name = "REWE Markt GmbH 4711"

      assert PayeeRenameCondition.matches?(condition(:contains, "markt gmbh"), name)
      assert PayeeRenameCondition.matches?(condition(:is, "rewe markt gmbh 4711"), name)
      assert PayeeRenameCondition.matches?(condition(:starts_with, "rewe markt"), name)
      assert PayeeRenameCondition.matches?(condition(:ends_with, "GMBH 4711"), name)

      refute PayeeRenameCondition.matches?(condition(:contains, "Aldi"), name)
      refute PayeeRenameCondition.matches?(condition(:is, "REWE Markt"), name)
      refute PayeeRenameCondition.matches?(condition(:starts_with, "Markt"), name)
      refute PayeeRenameCondition.matches?(condition(:ends_with, "REWE"), name)
    end

    test "matches umlauts and capitals beyond ASCII, composed or not" do
      assert PayeeRenameCondition.matches?(condition(:contains, "bÄckerei"), "Bäckerei Korn")
    end

    test "a blank condition matches nothing" do
      refute PayeeRenameCondition.matches?(condition(:contains, ""), "Rewe")
      refute PayeeRenameCondition.matches?(condition(:contains, "  "), "Rewe  Markt")
    end
  end

  test "blank?/1 is empty or whitespace only" do
    assert PayeeRenameCondition.blank?(nil)
    assert PayeeRenameCondition.blank?(" ")
    refute PayeeRenameCondition.blank?(" x ")
  end

  test "equivalent?/2 compares the operator and the text without case" do
    assert PayeeRenameCondition.equivalent?(condition(:is, "Aldi"), condition(:is, "ALDI"))
    refute PayeeRenameCondition.equivalent?(condition(:is, "Aldi"), condition(:contains, "Aldi"))
    refute PayeeRenameCondition.equivalent?(condition(:is, "Aldi"), condition(:is, "Aldi Nord"))
  end
end

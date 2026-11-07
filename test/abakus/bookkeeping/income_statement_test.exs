defmodule Abakus.Bookkeeping.IncomeStatementTest do
  use ExUnit.Case, async: true

  alias Abakus.Bookkeeping.{Category, IncomeStatement}

  test "every category's EÜR line is on the form, income among the income" do
    for %Category{euer: euer, kind: kind} <- Category.all(), euer != nil do
      lines =
        if kind == :income,
          do: IncomeStatement.income_kennzahlen(),
          else: IncomeStatement.expense_kennzahlen()

      assert euer in lines
    end
  end
end

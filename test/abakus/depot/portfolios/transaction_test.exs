defmodule Abakus.Depot.Portfolios.TransactionTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Portfolios.Transaction

  @form_types [:buy, :sell, :inbound_delivery, :outbound_delivery, :dividend, :deposit, :removal]

  test "every transaction of a type the form knows is editable, whatever its source" do
    for type <- Transaction.types(), source <- [:manual, :receipt] do
      assert Transaction.editable?(%Transaction{type: type, source: source}) ==
               type in @form_types
    end
  end
end

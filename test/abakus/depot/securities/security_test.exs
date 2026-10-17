defmodule Abakus.Depot.Securities.SecurityTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Securities.{AttributeType, Security}

  defp security(attributes), do: %Security{attributes: attributes}

  test "the TER is a built-in attribute, as a fraction" do
    assert Decimal.equal?(Security.ter(security(%{"ter" => 0.0022})), Decimal.new("0.0022"))
    assert Decimal.equal?(Security.ter(security(%{"ter" => 0})), Decimal.new(0))
    assert Security.ter(security(%{"vendor" => "iShares"})) == nil
    assert Security.ter(security(%{"ter" => "0,22 %"})) == nil
    assert Security.ter(%Security{attributes: nil}) == nil
  end

  test "the fund size is a built-in attribute, in cents" do
    assert Security.fund_size(security(%{"aum" => 1_780_000_000_000})) == 1_780_000_000_000
    assert Security.fund_size(security(%{})) == nil
    assert Security.fund_size(security(%{"aum" => 1.5})) == nil
  end

  test "every other attribute set comes with its type, in the order of the types" do
    [ter, aum, index, vendor, fee, listed] =
      for key <- ~w(ter aum index vendor fee listed), do: %AttributeType{key: key}

    security =
      security(%{
        "ter" => 0.0022,
        "aum" => 1_780_000_000_000,
        "vendor" => "Vanguard",
        "index" => "FTSE All-World",
        "fee" => nil,
        "listed" => false,
        "unknown" => "ohne Typ"
      })

    assert Security.attributes(security, [ter, aum, index, vendor, fee, listed]) ==
             [{index, "FTSE All-World"}, {vendor, "Vanguard"}, {listed, false}]

    assert Security.attributes(security(%{"vendor" => ""}), [vendor]) == []
    assert Security.attributes(%Security{attributes: nil}, [vendor]) == []
  end
end

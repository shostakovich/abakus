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

  test "sets the TER and the fund size given, keeping the others" do
    security = security(%{"ter" => 0.002, "aum" => 100, "vendor" => "iShares"})

    assert Security.ter_and_fund_size_changeset(security, 0.0015, 512_364_049_100).changes ==
             %{attributes: %{"ter" => 0.0015, "aum" => 512_364_049_100, "vendor" => "iShares"}}

    assert Security.ter_and_fund_size_changeset(security, nil, nil).changes == %{}

    assert Security.ter_and_fund_size_changeset(%Security{attributes: nil}, nil, 7).changes ==
             %{attributes: %{"aum" => 7}}
  end

  describe "changeset/2" do
    test "takes the ISIN without spaces, in capitals; a blank one removes it" do
      security = %Security{quote_feed: :manual, isin: "IE00B3RBWM25"}

      assert Security.changeset(security, %{isin: " ie00 b5ss qt16 "}).changes ==
               %{isin: "IE00B5SSQT16"}

      for blank <- ["", "  ", nil] do
        assert Security.changeset(security, %{isin: blank}).changes == %{isin: nil}
      end
    end

    test "takes the symbol without spaces around it and whether it is retired" do
      security = %Security{quote_feed: :yahoo, symbol: "VGWL.DE"}

      assert Security.changeset(security, %{symbol: " VWRL.AS ", retired: "true"}).changes ==
               %{symbol: "VWRL.AS", retired: true}

      assert Security.changeset(security, %{symbol: " VGWL.DE "}).changes == %{}
    end

    test "refuses an ISIN with a wrong check digit" do
      changeset = Security.changeset(%Security{quote_feed: :manual}, %{isin: "IE00B5SSQT17"})
      assert changeset.errors[:isin] == {"ist keine gültige ISIN.", []}
    end
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

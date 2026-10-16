defmodule Abakus.Depot.Receipts.ChecksTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.Depot.Receipts.{Check, Checks, Fields}

  @known MapSet.new(["IE00BK5BQT80"])
  @portfolios %{"1234567890" => %Portfolio{id: 7, name: "Sparplan"}}
  @text "Depot 123 456 7890 · IE00BK5BQT80 · Stück 93,207 · Kurs 12,0699 · 1.125,00 · SP-0001"

  defp fields(changes \\ []) do
    struct!(
      %Fields{
        kind: :purchase,
        isin: "IE00BK5BQT80",
        shares: Decimal.new("93.207"),
        price: Decimal.new("12.0699"),
        fees: Decimal.new("0"),
        amount: Decimal.new("1125.00"),
        depot_number: "123 456 7890",
        bank_reference: "SP-0001"
      },
      changes
    )
  end

  defp run(fields, booked_on \\ fn _reference -> nil end),
    do: Checks.run(fields, @text, @known, @portfolios, booked_on)

  defp check(checks, name), do: Enum.find(checks, &(&1.name == name))

  defp passed?(checks), do: Enum.all?(checks, &(&1.result == :passed))

  test "passes a receipt that adds up, with a known ISIN and a new reference" do
    checks = run(fields())

    assert passed?(checks)
    refute Checks.duplicate?(checks)
    assert Decimal.equal?(check(checks, :amount).computed, "1125.00")
  end

  test "allows the amount the four-decimal price's rounding explains" do
    # Up to 1000 × 0.00005 + 0.005 = 0.055 off is rounding.
    trade = fields(shares: Decimal.new("1000"), price: Decimal.new("10"))

    assert %Check{result: :passed} =
             trade |> struct!(amount: Decimal.new("10000.05")) |> run() |> check(:amount)

    assert %Check{result: :failed} =
             trade |> struct!(amount: Decimal.new("10000.06")) |> run() |> check(:amount)
  end

  test "adds fees and taxes to a purchase and takes them off a sale or dividend" do
    purchase = fields(fees: Decimal.new("1.00"), taxes: Decimal.new("2.00"))
    assert %Check{result: :failed, computed: computed} = purchase |> run() |> check(:amount)
    assert Decimal.equal?(computed, "1128.00")

    sale = fields(kind: :sale, fees: Decimal.new("1.00"), amount: Decimal.new("1124.00"))
    assert %Check{result: :passed} = sale |> run() |> check(:amount)

    dividend =
      fields(
        kind: :dividend,
        shares: Decimal.new("100"),
        price: Decimal.new("0.25"),
        fees: nil,
        taxes: Decimal.new("6.59"),
        amount: Decimal.new("18.41")
      )

    assert %Check{result: :passed} = dividend |> run() |> check(:amount)
  end

  test "cannot check the amount without shares, price or amount" do
    for missing <- [:shares, :price, :amount] do
      assert %Check{result: :missing} = fields([{missing, nil}]) |> run() |> check(:amount)
    end
  end

  test "checks the ISIN's check digit and whether the security is known" do
    assert %Check{result: :failed} = fields(isin: "IE00BK5BQT81") |> run() |> check(:isin)
    assert %Check{result: :new_security} = fields(isin: "US0378331005") |> run() |> check(:isin)
    assert %Check{result: :missing} = fields(isin: nil) |> run() |> check(:isin)
  end

  test "finds the portfolio of the depot number by its digits" do
    checks = fields(depot_number: "1234-567-890") |> run()

    assert %Check{result: :passed, portfolio_id: 7, portfolio_name: "Sparplan"} =
             check(checks, :depot)

    assert Checks.portfolio(checks) == {7, "Sparplan"}
  end

  test "fails a depot number of none of the user's portfolios" do
    checks = fields(depot_number: "4472") |> run()

    assert %Check{result: :failed} = check(checks, :depot)
    assert Checks.portfolio(checks) == nil
    refute passed?(checks)
    assert %Check{result: :missing} = fields(depot_number: nil) |> run() |> check(:depot)
  end

  test "marks a receipt whose reference was booked already" do
    checks = run(fields(), fn "SP-0001" -> ~D[2026-09-18] end)

    assert %Check{result: :failed, booked_on: ~D[2026-09-18]} = check(checks, :reference)
    assert Checks.duplicate?(checks)
    refute passed?(checks)

    assert %Check{result: :missing} = fields(bank_reference: nil) |> run() |> check(:reference)
  end

  test "fails values the receipt's text does not have" do
    assert %Check{result: :passed} = fields() |> run() |> check(:found)

    assert %Check{result: :failed, not_found: [:price, :amount]} =
             fields(price: Decimal.new("145.76"), amount: Decimal.new("13586.00"))
             |> run()
             |> check(:found)
  end

  test "correctable/2 checks amount, values found and the ISIN's check digit only" do
    assert [%Check{name: :amount}, %Check{name: :found}, %Check{name: :isin, result: :passed}] =
             checks = Checks.correctable(fields(isin: "US0378331005"), @text <> " US0378331005")

    refute Checks.correction_needed?(checks)
  end

  test "correction_needed?/1 when the amount does not add up or the ISIN is invalid" do
    assert Checks.correction_needed?(
             Checks.correctable(fields(amount: Decimal.new("1.125")), @text)
           )

    assert Checks.correction_needed?(Checks.correctable(fields(isin: "IE00BK5BQT81"), @text))
    refute Checks.correction_needed?(Checks.correctable(fields(date: ~D[2026-10-02]), @text))
  end

  test "correction_needed?/1 when shares, price or amount are missing, but not for another kind" do
    assert Checks.correction_needed?(Checks.correctable(fields(shares: nil), @text))
    assert Checks.correction_needed?(Checks.correctable(fields(price: nil), @text))
    assert Checks.correction_needed?(Checks.correctable(fields(amount: nil), @text))

    assert Checks.correctable(fields(kind: :other, shares: nil), @text) == []
    refute Checks.correction_needed?([])
  end

  test "formula/1 names the amount check's sum" do
    assert Checks.formula(fields(fees: Decimal.new("1"))) == "Stück × Kurs + Gebühren"

    assert Checks.formula(fields(kind: :dividend, taxes: Decimal.new("2"))) ==
             "Stück × Dividende − Steuern"
  end
end

defmodule Abakus.Bookkeeping.VatTest do
  use ExUnit.Case, async: true

  alias Abakus.Bookkeeping.Vat

  test "takes the VAT out of a gross amount, rounded to the cent" do
    assert Vat.amounts(-11_900, :rate_19, ~D[2026-03-01]) == %{net: -10_000, vat: -1_900}
    assert Vat.amounts(-2_368, :rate_19, ~D[2026-03-01]) == %{net: -1_990, vat: -378}
    assert Vat.amounts(10_700, :rate_7, ~D[2026-03-01]) == %{net: 10_000, vat: 700}
    assert Vat.amounts(-5_000, :rate_0, ~D[2026-03-01]) == %{net: -5_000, vat: 0}
  end

  test "under reverse charge the amount is net and the standard rate of its date applies" do
    assert Vat.amounts(-10_000, :reverse_charge, ~D[2027-02-10]) == %{net: -10_000, vat: -1_900}
    assert Vat.amounts(-10_000, :reverse_charge, ~D[2020-08-01]) == %{net: -10_000, vat: -1_600}
  end

  test "knows the treatment of a rate" do
    assert Vat.treatment(16) == :rate_16
    assert Vat.rate(:rate_16) == 16
    assert Vat.treatment(8) == nil
  end
end

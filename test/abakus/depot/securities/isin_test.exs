defmodule Abakus.Depot.Securities.ISINTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Securities.ISIN

  test "accepts ISINs with the right check digit" do
    for isin <- ~w(IE00B3RBWM25 IE00B5SSQT16 LU2581375156 US0378331005 DE000A1EWWW0) do
      assert ISIN.valid?(isin), isin
    end
  end

  test "refuses a wrong check digit, a wrong form and no string" do
    refute ISIN.valid?("IE00B3RBWM26")
    refute ISIN.valid?("US0378331006")
    refute ISIN.valid?("ie00b3rbwm25")
    refute ISIN.valid?("IE00B3RBWM2")
    refute ISIN.valid?("1E00B3RBWM25")
    refute ISIN.valid?(nil)
  end
end

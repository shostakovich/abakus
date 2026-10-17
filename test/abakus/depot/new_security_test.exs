defmodule Abakus.Depot.NewSecurityTest do
  use Abakus.DataCase

  import Abakus.Depot.SecuritiesFixtures
  import Abakus.UsersFixtures

  alias Abakus.Depot.{FakeSymbolSearch, MarketData, Securities}
  alias Abakus.Depot.Securities.Security

  setup do
    %{scope: user_scope_fixture()}
  end

  test "stores name and symbol that Yahoo's search found for the ISIN", %{scope: scope} do
    FakeSymbolSearch.stub(fn _isin ->
      {:ok, [%{symbol: "IS3N.DE", name: "iShares Core MSCI EM IMI", exchange: "GER"}]}
    end)

    {:ok, found} = MarketData.lookup_isin("IE00BKM4GZ66")

    assert {:ok, security} =
             Securities.create_security(scope, Map.put(found, :isin, " ie00bkm4gz66 "))

    assert %Security{
             isin: "IE00BKM4GZ66",
             name: "iShares Core MSCI EM IMI",
             symbol: "IS3N.DE",
             quote_feed: :yahoo,
             currency: "EUR"
           } = Repo.reload!(security)
  end

  test "without a symbol its prices are entered by hand", %{scope: scope} do
    {:ok, security} = Securities.create_security(scope, %{isin: "IE00BKM4GZ66", name: "EM IMI"})
    assert %{quote_feed: :manual, symbol: nil} = security
  end

  test "refuses a wrong check digit and an ISIN that a security has", %{scope: scope} do
    {:error, changeset} = Securities.create_security(scope, %{isin: "IE00BKM4GZ67", name: "EM"})
    assert errors_on(changeset).isin == ["ist keine gültige ISIN"]

    security_fixture(isin: "IE00BKM4GZ66", name: "EM IMI")
    {:error, changeset} = Securities.create_security(scope, %{isin: "IE00BKM4GZ66", name: "EM"})
    assert errors_on(changeset).isin == ["gehört schon zu EM IMI"]
  end
end

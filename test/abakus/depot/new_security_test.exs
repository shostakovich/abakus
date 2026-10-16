defmodule Abakus.Depot.NewSecurityTest do
  use Abakus.DataCase

  import Abakus.Depot.SecuritiesFixtures
  import Abakus.UsersFixtures

  alias Abakus.Depot.{FakeSymbolSearch, MarketData, PPImport, Securities}
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
             currency: "EUR",
             source: :manual
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

  test "a PP re-import neither takes over nor deletes a security created from an ISIN",
       %{scope: scope} do
    {:ok, created} =
      Securities.create_security(scope, %{isin: "IE00B4L5Y983", name: "Mein MSCI World"})

    {:ok, _summary} = PPImport.run(scope, "test/fixtures/depot/pp/sample.portfolio")
    {:ok, _summary} = PPImport.run(scope, "test/fixtures/depot/pp/sample.portfolio")

    assert %{name: "Mein MSCI World", source: :manual} = Repo.reload!(created)
    assert Repo.aggregate(from(s in Security, where: s.isin == "IE00B4L5Y983"), :count) == 2
  end
end

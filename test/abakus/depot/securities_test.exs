defmodule Abakus.Depot.SecuritiesTest do
  use Abakus.DataCase

  import Abakus.Depot.SecuritiesFixtures

  alias Abakus.Depot.Securities
  alias Abakus.Users.Scope

  @scope %Scope{}

  describe "get_security/2" do
    test "gives any security by id, as securities are shared, and nil for an unknown one" do
      security = security_fixture()

      assert Securities.get_security(@scope, security.id) == security
      assert Securities.get_security(@scope, security.id + 1) == nil
    end
  end

  describe "store_yahoo_prices/2" do
    test "adds new days and replaces Yahoo prices, but keeps manual ones" do
      security = security_fixture()
      price_fixture(security, ~D[2026-10-05], 100, :manual)
      price_fixture(security, ~D[2026-10-06], 200, :manual)
      price_fixture(security, ~D[2026-10-07], 300, :yahoo)

      Securities.store_yahoo_prices(security, [
        {~D[2026-10-05], 101},
        {~D[2026-10-06], 201},
        {~D[2026-10-07], 301},
        {~D[2026-10-08], 401}
      ])

      assert prices_of(security) == [
               {~D[2026-10-05], 100, :manual},
               {~D[2026-10-06], 200, :manual},
               {~D[2026-10-07], 301, :yahoo},
               {~D[2026-10-08], 401, :yahoo}
             ]
    end
  end

  describe "claim_unchecked_yahoo_securities/2" do
    test "claims each unchecked Yahoo security once" do
      unchecked = security_fixture()
      security_fixture(symbol: "LDGL.DE", checked_at: ~U[2026-10-09 15:50:00.000000Z])
      security_fixture(quote_feed: :manual, symbol: nil)
      now = ~U[2026-10-09 16:00:00.000000Z]

      assert [%{id: id}] =
               Securities.claim_unchecked_yahoo_securities(~U[2026-10-09 15:45:00.000000Z], now)

      assert id == unchecked.id

      assert Securities.claim_unchecked_yahoo_securities(~U[2026-10-09 15:45:00.000000Z], now) ==
               []
    end

    test "only reads while every Yahoo security is checked, so it waits for no other write" do
      security_fixture(checked_at: ~U[2026-10-09 15:50:00.000000Z])
      handler = make_ref()

      :telemetry.attach(
        handler,
        [:abakus, :repo, :query],
        &__MODULE__.report_query/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      Securities.claim_unchecked_yahoo_securities(
        ~U[2026-10-09 15:45:00.000000Z],
        ~U[2026-10-09 16:00:00.000000Z]
      )

      assert_received {:query, "SELECT" <> _query}
      refute_received {:query, "UPDATE" <> _query}
    end
  end

  def report_query(_event, _measurements, %{query: query}, test), do: send(test, {:query, query})

  describe "with_same_yahoo_symbol/2" do
    test "skips a security whose symbol or feed changed" do
      security = security_fixture()

      assert Securities.with_same_yahoo_symbol(security, & &1.symbol) == "VGWL.DE"

      {:ok, _} =
        Securities.update_quote_feed(@scope, security, %{quote_feed: "yahoo", symbol: "VWRL.AS"})

      assert Securities.with_same_yahoo_symbol(security, & &1.symbol) == :skipped
    end
  end

  describe "list_closes_since/2" do
    test "starts at the last close on or before the date, or at the first one" do
      security = security_fixture()
      later = security_fixture(name: "Später notiert")

      for {date, close} <- [{~D[2026-10-01], 1}, {~D[2026-10-02], 2}, {~D[2026-10-05], 5}],
          do: price_fixture(security, date, close, :manual)

      price_fixture(later, ~D[2026-10-05], 50, :manual)
      price_fixture(security_fixture(name: "Nicht gefragt"), ~D[2026-10-05], 9, :manual)

      assert Enum.sort(Securities.list_closes_since([security.id, later.id], ~D[2026-10-03])) ==
               [
                 {security.id, ~D[2026-10-02], 2},
                 {security.id, ~D[2026-10-05], 5},
                 {later.id, ~D[2026-10-05], 50}
               ]
    end
  end

  describe "last_price_date/1" do
    test "is the date of the last price from any source" do
      security = security_fixture()
      assert Securities.last_price_date(security) == nil

      price_fixture(security, ~D[2026-10-01], 100, :manual)
      price_fixture(security, ~D[2026-09-01], 100, :yahoo)

      assert Securities.last_price_date(security) == ~D[2026-10-01]
    end
  end

  describe "update_quote_feed/3" do
    setup do
      security =
        security_fixture(fetched_at: ~U[2026-10-09 16:00:00.000000Z], fetch_error: "Fehler")

      price_fixture(security, ~D[2026-10-05], 100, :manual)
      price_fixture(security, ~D[2026-10-06], 200, :manual)
      price_fixture(security, ~D[2026-10-07], 300, :yahoo)
      %{security: security}
    end

    test "a new symbol drops the Yahoo prices of the old one", %{security: security} do
      assert {:ok, updated} =
               Securities.update_quote_feed(@scope, security, %{
                 quote_feed: "yahoo",
                 symbol: "VWRL.AS"
               })

      assert updated.symbol == "VWRL.AS"
      assert {updated.fetched_at, updated.fetch_error} == {nil, nil}

      assert prices_of(security) == [
               {~D[2026-10-05], 100, :manual},
               {~D[2026-10-06], 200, :manual}
             ]
    end

    test "a switch back to Yahoo drops the Yahoo prices and the quote of the old symbol", %{
      security: security
    } do
      {:ok, manual} = Securities.update_quote_feed(@scope, security, %{quote_feed: "manual"})

      security
      |> Ecto.Changeset.change(latest_close: 1, latest_date: ~D[2026-10-07])
      |> Repo.update!()

      assert {:ok, updated} = Securities.update_quote_feed(@scope, manual, %{quote_feed: "yahoo"})

      assert {updated.latest_close, updated.latest_date} == {nil, nil}

      assert prices_of(security) == [
               {~D[2026-10-05], 100, :manual},
               {~D[2026-10-06], 200, :manual}
             ]
    end

    test "switching to manual keeps the Yahoo prices", %{security: security} do
      assert {:ok, updated} =
               Securities.update_quote_feed(@scope, security, %{quote_feed: "manual", symbol: ""})

      assert updated.quote_feed == :manual
      assert length(prices_of(security)) == 3
    end

    test "Yahoo needs a symbol", %{security: security} do
      assert {:error, changeset} =
               Securities.update_quote_feed(@scope, security, %{quote_feed: "yahoo", symbol: ""})

      assert "can't be blank" in errors_on(changeset).symbol
    end
  end

  describe "compositions" do
    test "replace_composition/3 stores one per security, and list_compositions/1 finds them" do
      [world, em, other] = for isin <- ~w(A B C), do: security_fixture(isin: isin)
      now = ~U[2026-10-09 16:00:00.000000Z]
      Securities.replace_composition(world, %{countries: %{"US" => 1}, sectors: %{}}, now)
      composition_fixture(em, %{"BR" => 1})
      composition_fixture(other, %{"JP" => 1})
      later = DateTime.add(now, 1, :day)

      Securities.replace_composition(
        world,
        %{countries: %{"JP" => 1}, sectors: %{"E" => 1}},
        later
      )

      compositions = Securities.list_compositions([world.id, em.id])

      assert compositions |> Map.keys() |> Enum.sort() == [world.id, em.id]
      assert %{countries: %{"JP" => 1}, sectors: %{"E" => 1}} = compositions[world.id]
      assert compositions[world.id].fetched_at == later
      assert %{countries: %{"BR" => 1}} = compositions[em.id]
    end

    test "list_securities_with_isin/0 leaves out securities without an ISIN and retired ones" do
      with_isin = security_fixture(isin: "IE00B3RBWM25")
      security_fixture(isin: nil)
      security_fixture(isin: "")
      security_fixture(isin: "IE00B4L5Y983", retired: true)

      assert Securities.list_securities_with_isin() == [with_isin]
    end
  end

  describe "profile/2" do
    test "gives TER, fund size and every other attribute set with its type for securities" do
      vendor = attribute_type_fixture("vendor", "Anbieter", "StringConverter")
      attribute_type_fixture("index", "Index", "StringConverter", "Account")
      index = attribute_type_fixture("index", "Index", "StringConverter")

      security =
        security_fixture(
          attributes: %{"ter" => 0.002, "aum" => 100, "index" => "Welt", "vendor" => "Anbieter A"}
        )

      profile = Securities.profile(@scope, security)

      assert Decimal.equal?(profile.ter, Decimal.new("0.002"))
      assert profile.fund_size == 100
      assert profile.attributes == [{vendor, "Anbieter A"}, {index, "Welt"}]
      assert profile.composition == nil
    end

    test "gives the regions and sectors of its composition" do
      security = security_fixture()
      composition_fixture(security, %{"US" => 1}, %{"Energy" => 1})

      assert %{regions: [%{key: :usa}], sectors: [%{key: "Energy"}], as_of: as_of} =
               Securities.profile(@scope, security).composition

      assert as_of == composition_of(security).fetched_at
    end
  end
end

defmodule Abakus.Depot.SecuritiesTest do
  use Abakus.DataCase

  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures, TaxonomiesFixtures}
  import Abakus.UsersFixtures

  alias Abakus.Depot.{Securities, Settings}
  alias Abakus.Depot.Securities.{Price, Security}
  alias Abakus.Depot.Taxonomies.Assignment
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
        Securities.update_security(@scope, security, %{quote_feed: "yahoo", symbol: "VWRL.AS"})

      assert Securities.with_same_yahoo_symbol(security, & &1.symbol) == :skipped
    end
  end

  describe "with_same_isin/2" do
    test "skips a security whose ISIN changed or was removed" do
      security = security_fixture(isin: "IE00B3RBWM25")

      assert Securities.with_same_isin(security, & &1.isin) == "IE00B3RBWM25"

      {:ok, changed} = update_isin(security, "IE00B5SSQT16")
      assert Securities.with_same_isin(security, & &1.isin) == :skipped

      {:ok, removed} = update_isin(changed, "")
      assert Securities.with_same_isin(changed, & &1.isin) == :skipped
      assert Securities.with_same_isin(removed, & &1.isin) == :skipped
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

  describe "update_security/3" do
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
               Securities.update_security(@scope, security, %{
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
      {:ok, manual} = Securities.update_security(@scope, security, %{quote_feed: "manual"})

      security
      |> Ecto.Changeset.change(latest_close: 1, latest_date: ~D[2026-10-07])
      |> Repo.update!()

      assert {:ok, updated} = Securities.update_security(@scope, manual, %{quote_feed: "yahoo"})

      assert {updated.latest_close, updated.latest_date} == {nil, nil}

      assert prices_of(security) == [
               {~D[2026-10-05], 100, :manual},
               {~D[2026-10-06], 200, :manual}
             ]
    end

    test "switching to manual keeps the Yahoo prices", %{security: security} do
      assert {:ok, updated} =
               Securities.update_security(@scope, security, %{quote_feed: "manual", symbol: ""})

      assert updated.quote_feed == :manual
      assert length(prices_of(security)) == 3
    end

    test "Yahoo needs a symbol", %{security: security} do
      assert {:error, changeset} =
               Securities.update_security(@scope, security, %{quote_feed: "yahoo", symbol: ""})

      assert "can't be blank" in errors_on(changeset).symbol
    end
  end

  describe "update_security/3 with an ISIN" do
    defp update_isin(security, isin),
      do:
        Securities.update_security(@scope, security, %{
          quote_feed: "yahoo",
          symbol: "VGWL.DE",
          isin: isin
        })

    test "adds an ISIN, without spaces and in capitals, and a blank one removes it" do
      security = security_fixture(isin: nil)

      assert {:ok, %{isin: "IE00B3RBWM25"} = updated} = update_isin(security, " ie00 b3rb wm25 ")
      assert {:ok, %{isin: nil}} = update_isin(updated, "  ")
    end

    test "refuses an invalid ISIN and one another security has, but keeps its own" do
      security = security_fixture(isin: "IE00B3RBWM25")
      security_fixture(isin: "IE00B5SSQT16", name: "HSBC MSCI Emerging Markets")

      assert {:error, changeset} = update_isin(security, "IE00B3RBWM26")
      assert errors_on(changeset).isin == ["ist keine gültige ISIN."]

      assert {:error, changeset} = update_isin(security, "ie00b5ssqt16")
      assert errors_on(changeset).isin == ["gehört schon zu HSBC MSCI Emerging Markets."]

      assert {:ok, %{isin: "IE00B3RBWM25"}} = update_isin(security, "IE00B3RBWM25")
    end

    test "a new or removed ISIN drops DivvyDiary's error for the old one" do
      security = security_fixture(isin: "IE00B3RBWM25", divvy_diary_error: "kennt sie nicht")

      assert {:ok, %{divvy_diary_error: "kennt sie nicht"} = same} =
               update_isin(security, "IE00B3RBWM25")

      assert {:ok, %{divvy_diary_error: nil}} = update_isin(same, "IE00B5SSQT16")

      unknown = security_fixture(isin: "IE00B4L5Y983", divvy_diary_unknown: true)
      assert {:ok, %{divvy_diary_unknown: false}} = update_isin(unknown, "IE00BKM4GZ66")
    end

    test "a new ISIN drops a TER stored after the security was read" do
      security = security_fixture(isin: "IE00B3RBWM25")
      Securities.store_ter_and_fund_size(Repo.reload!(security), 0.0022, 9_000_000)

      assert {:ok, updated} = update_isin(security, "IE00B5SSQT16")

      assert updated.attributes == %{}
      assert Repo.reload!(security).attributes == %{}
    end

    test "a new or removed ISIN drops what DivvyDiary delivered for the old one" do
      for {isin, new_isin} <- [{"IE00B3RBWM25", "IE00B5SSQT16"}, {"IE00B4L5Y983", ""}] do
        security =
          security_fixture(
            isin: isin,
            attributes: %{"ter" => 0.002, "aum" => 100, "vendor" => "Vanguard"}
          )

        composition_fixture(security, %{"US" => 1})
        divvy_diary_dividend_fixture(security, ~D[2026-03-12], ~D[2026-03-25], 0.15)

        {:ok, same} = update_isin(security, isin)
        assert composition_of(same) != nil
        assert same.attributes["ter"] == 0.002

        {:ok, updated} = update_isin(same, new_isin)
        assert composition_of(updated) == nil
        assert Securities.list_divvy_diary_dividends([security.id]) == []
        assert Repo.reload!(security).attributes == %{"vendor" => "Vanguard"}
      end
    end
  end

  describe "update_security/3 retiring" do
    test "retires a security and brings it back" do
      security = security_fixture()

      assert {:ok, %{retired: true} = retired} =
               Securities.update_security(@scope, security, %{retired: "true"})

      assert {:ok, %{retired: false}} =
               Securities.update_security(@scope, retired, %{retired: "false"})
    end
  end

  test "record_divvy_diary_error/2 records why DivvyDiary delivered nothing, nil clears it" do
    security = security_fixture(isin: "IE00B3RBWM25", divvy_diary_unknown: true)

    failed = Securities.record_divvy_diary_error(security, "DivvyDiary ist nicht erreichbar.")

    assert %{divvy_diary_error: "DivvyDiary ist nicht erreichbar.", divvy_diary_unknown: false} =
             Repo.reload!(failed)

    assert Securities.record_divvy_diary_error(failed, nil).divvy_diary_error == nil
  end

  test "record_divvy_diary_unknown/1 records an ISIN DivvyDiary does not know, not as an error" do
    security = security_fixture(isin: "IE00B3RBWM25", divvy_diary_error: "alt")

    Securities.record_divvy_diary_unknown(security)

    assert %{divvy_diary_error: nil, divvy_diary_unknown: true} = Repo.reload!(security)
  end

  describe "delete_security/2" do
    setup do
      scope = user_scope_fixture()
      %{scope: scope, security: security_fixture(isin: "IE00B3RBWM25")}
    end

    test "deletes a security with its prices, composition, DivvyDiary dividends and assignments",
         %{scope: scope, security: security} do
      price_fixture(security, ~D[2026-10-05], 100, :yahoo)
      composition_fixture(security, %{"US" => 1})
      divvy_diary_dividend_fixture(security, ~D[2026-03-12], ~D[2026-03-25], 0.15)
      {_taxonomy, root} = taxonomy_fixture(scope)
      assignment_fixture(root, security)
      kept = security_fixture(name: "Bleibt")

      refute Securities.booked?(scope, security)
      assert {:ok, _deleted} = Securities.delete_security(scope, security)

      assert Repo.all(Security) == [kept]
      assert Repo.all(Price) == []
      assert composition_of(security) == nil
      assert Securities.list_divvy_diary_dividends([security.id]) == []
      assert Repo.all(Assignment) == []
    end

    test "keeps a security any user has booked", %{scope: scope, security: security} do
      other = user_scope_fixture()
      portfolio = portfolio_fixture(other)

      transaction_fixture(other, ~D[2026-10-01],
        type: :inbound_delivery,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(1)
      )

      assert Securities.booked?(scope, security)
      assert Securities.delete_security(scope, security) == {:error, :booked}
      assert Repo.reload(security)
    end

    test "keeps a security any user compares with", %{scope: scope, security: security} do
      {:ok, _setting} = Settings.update_benchmark(user_scope_fixture(), security.id)

      assert Securities.delete_security(scope, security) == {:error, :benchmark}
      assert Repo.reload(security)
    end

    test "keeps a security another user has assigned", %{scope: scope, security: security} do
      {_taxonomy, root} = taxonomy_fixture(user_scope_fixture())
      assignment_fixture(root, security)

      assert Securities.usage(scope, security).assigned
      assert Securities.delete_security(scope, security) == {:error, :assigned}
      assert Repo.reload(security)
    end
  end

  describe "usage/2" do
    test "tells booked, held and anyone's benchmark apart" do
      scope = user_scope_fixture()
      other = user_scope_fixture()
      security = security_fixture()
      portfolio = portfolio_fixture(other)

      assert Securities.usage(scope, security) ==
               %{booked: false, held: false, benchmark: false, assigned: false}

      transaction_fixture(other, ~D[2026-10-01],
        type: :inbound_delivery,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(2)
      )

      assert %{booked: true, held: true} = Securities.usage(scope, security)

      transaction_fixture(other, ~D[2026-10-02],
        type: :outbound_delivery,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(2)
      )

      {:ok, _setting} = Settings.update_benchmark(other, security.id)

      assert Securities.usage(scope, security) ==
               %{booked: true, held: false, benchmark: true, assigned: false}
    end
  end

  test "get_security_by_isin/2 finds the security with an ISIN" do
    security = security_fixture(isin: "IE00B3RBWM25")

    assert Securities.get_security_by_isin(@scope, "IE00B3RBWM25") == security
    assert Securities.get_security_by_isin(@scope, "IE00B5SSQT16") == nil
  end

  test "divvy_diary_fetched_at/2 is when the composition came, nil before" do
    security = security_fixture()
    assert Securities.divvy_diary_fetched_at(@scope, security) == nil

    composition_fixture(security, %{"US" => 1})
    assert Securities.divvy_diary_fetched_at(@scope, security) == ~U[2026-10-08 12:00:00.000000Z]
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

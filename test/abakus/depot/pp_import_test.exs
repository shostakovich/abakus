defmodule Abakus.Depot.PPImportTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures, only: [budget_scope: 0]
  import Abakus.Depot.SecuritiesFixtures, only: [security_fixture: 1]
  import Abakus.UsersFixtures

  alias Abakus.Depot.{
    AccountRoles,
    BudgetFeed,
    BudgetLink,
    Portfolios,
    PPImport,
    Securities,
    Settings,
    Taxonomies
  }

  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.Depot.PPImport.Reader
  alias Abakus.Depot.Securities.{Price, Security}
  alias Abakus.{DomainFixtures, Ledger}

  @sample "test/fixtures/depot/pp/sample.portfolio"

  setup do
    {:ok, client} = Reader.read(@sample)
    %{scope: user_scope_fixture(), client: client}
  end

  defp security(isin), do: Repo.get_by!(Security, isin: isin)

  defp import_unchanged?(summary) do
    Enum.all?(summary, fn {_kind, counts} -> Enum.all?(counts, fn {_op, n} -> n == 0 end) end)
  end

  defp transaction(scope, type),
    do: Enum.find(Portfolios.list_transactions(scope), &(&1.type == type))

  describe "importing the sample file" do
    setup %{scope: scope} do
      {:ok, summary} = PPImport.run(scope, @sample)
      %{summary: summary}
    end

    test "creates every object once", %{summary: summary} do
      assert summary.securities.created == 4
      assert summary.accounts.created == 3
      assert summary.portfolios.created == 2
      assert summary.transactions.created == 21
      assert summary.savings_plans.created == 2
      assert summary.taxonomies.created == 1
      assert summary.classifications.created == 5
      assert summary.assignments.created == 5
      assert summary.prices.created == 7
    end

    test "takes over every transaction type", %{scope: scope} do
      types = scope |> Portfolios.list_transactions() |> Enum.map(& &1.type) |> MapSet.new()
      assert types == MapSet.new(Transaction.types())
    end

    test "keeps a buy as one transaction with both sides and its units", %{scope: scope} do
      [depot_a, _] = Portfolios.list_portfolios(scope)
      [account_a | _] = Portfolios.list_accounts(scope)

      buy = Enum.find(Portfolios.list_transactions(scope), &(&1.note == "Erstkauf"))
      assert %{type: :buy, amount: 100_550, shares: 1_000_000_000, currency: "EUR"} = buy
      assert buy.portfolio_id == depot_a.id
      assert buy.account_id == account_a.id
      assert buy.security_id == security("IE00B4L5Y983").id
      assert buy.date_time == ~N[2024-01-02 09:00:00]
      assert buy.pp_other_uuid

      assert [%{type: :fee, amount: 450}, %{type: :tax, amount: 100}] =
               Enum.sort_by(buy.units, & &1.type)
    end

    test "keeps foreign currency units with their rate", %{scope: scope} do
      buy = Enum.find(Portfolios.list_transactions(scope), &(&1.amount == 83_000))
      gross = Enum.find(buy.units, &(&1.type == :gross_value))

      assert %{amount: 82_800, currency: "EUR", fx_amount: 90_000, fx_currency: "USD"} = gross
      assert Decimal.equal?(gross.fx_rate, Decimal.new("0.92"))
    end

    test "keeps a dividend's ex date and withholding tax", %{scope: scope} do
      dividend = transaction(scope, :dividend)

      assert %{amount: 93, shares: 500_000_000, ex_date: ~N[2024-02-09 00:00:00]} = dividend
      assert dividend.security_id == security("US0378331005").id
      assert Enum.map(dividend.units, & &1.type) |> Enum.sort() == [:gross_value, :tax]
    end

    test "points transfers at both sides", %{scope: scope} do
      [depot_a, depot_b] = Portfolios.list_portfolios(scope)
      [account_a, account_b, _usd] = Portfolios.list_accounts(scope)

      security_transfer = transaction(scope, :security_transfer)
      assert security_transfer.portfolio_id == depot_a.id
      assert security_transfer.other_portfolio_id == depot_b.id

      cash_transfer = transaction(scope, :cash_transfer)
      assert cash_transfer.account_id == account_a.id
      assert cash_transfer.other_account_id == account_b.id
      assert cash_transfer.note == "Umbuchung"
    end

    test "sets reference accounts", %{scope: scope} do
      [depot_a, depot_b] = Portfolios.list_portfolios(scope)
      [account_a, account_b, _usd] = Portfolios.list_accounts(scope)

      assert depot_a.reference_account_id == account_a.id
      assert depot_b.reference_account_id == account_b.id
    end

    test "maps PP and Yahoo feeds to Yahoo symbols, others to manual prices" do
      assert %{quote_feed: :yahoo, symbol: "EUNL.DE", pp_feed: "YAHOO"} = security("IE00B4L5Y983")
      assert %{quote_feed: :yahoo, symbol: "XMME.DE", pp_feed: "PP"} = security("IE00BTJRMP35")
      assert %{quote_feed: :manual, symbol: nil, currency: "USD"} = security("US0378331005")
      assert %{retired: true, isin: nil} = Repo.get_by!(Security, name: "Altfonds ohne ISIN")
    end

    test "keeps attributes, latest price and price history", %{scope: scope} do
      world = security("IE00B4L5Y983")

      assert world.attributes == %{
               "ter" => 0.002,
               "aum" => 1_234_500_000_000,
               "vendor" => "iShares"
             }

      assert Decimal.equal?(Security.ter(world), Decimal.new("0.002"))
      assert Security.fund_size(world) == 1_234_500_000_000
      assert world.latest_date == ~D[2024-03-04]
      assert world.latest_close == 9_095_000_000

      assert [%{date: ~D[2024-01-02], close: 8_510_000_000, source: :pp} | _] =
               Securities.list_prices(scope, world)
    end

    test "links savings plans to their transactions", %{scope: scope} do
      [monthly, weekly] = Portfolios.list_savings_plans(scope)

      assert %{name: "Sparplan World", type: :purchase_or_delivery, interval: 1} = monthly
      assert %{amount: 10_000, fees: 100, start: ~D[2024-02-01]} = monthly
      assert Enum.map(monthly.transactions, & &1.type) == [:buy, :buy]

      assert %{name: "Wöchentliche Einlage", type: :deposit, interval: 101} = weekly
      assert [%{type: :deposit, amount: 2_500}] = weekly.transactions
    end

    test "keeps target weights and assigns securities and accounts", %{scope: scope} do
      [taxonomy] = Taxonomies.list_taxonomies(scope)
      by_name = Map.new(taxonomy.classifications, &{&1.name, &1})

      assert by_name["Aktien"].weight == 9_000
      assert by_name["Industrieländer"].parent_id == by_name["Aktien"].id
      assert by_name["Aktien"].parent_id == by_name["Asset Allocation"].id

      apple = security("US0378331005")

      assert Enum.any?(
               by_name["Industrieländer"].assignments,
               &(&1.security_id == apple.id and &1.weight == 5_000)
             )

      [_a, account_b, _usd] = Portfolios.list_accounts(scope)
      assert [%{account_id: account_id, security_id: nil}] = by_name["Risikofrei"].assignments
      assert account_id == account_b.id
    end

    test "a second import changes nothing", %{scope: scope} do
      assert {:ok, summary} = PPImport.run(scope, @sample)
      assert import_unchanged?(summary)
    end
  end

  test "updates and deletes what changed in the file", %{scope: scope, client: client} do
    {:ok, _} = PPImport.import_client(scope, client)

    [first | rest] = client.transactions
    old_fund = Enum.find(client.securities, &(&1.isin == nil))
    [taxonomy] = client.taxonomies
    [plan | plans] = client.plans

    changed = %{
      client
      | transactions: [%{first | amount: first.amount + 1} | Enum.drop(rest, 1)],
        securities: List.delete(client.securities, old_fund),
        taxonomies: [
          %{
            taxonomy
            | classifications: Enum.reject(taxonomy.classifications, &(&1.name == "Risikofrei"))
          }
        ],
        plans: [%{plan | amount: 20_000} | plans]
    }

    assert {:ok, summary} = PPImport.import_client(scope, changed)

    assert summary.transactions == %{created: 0, updated: 1, deleted: 1}
    assert summary.securities.deleted == 1
    assert summary.classifications.deleted == 1
    assert summary.savings_plans == %{created: 2, updated: 0, deleted: 2}

    assert length(Portfolios.list_transactions(scope)) == 20
    refute Repo.get_by(Security, name: "Altfonds ohne ISIN")
    assert Enum.any?(Portfolios.list_savings_plans(scope), &(&1.amount == 20_000))
  end

  describe "with the Depot linked to the budget" do
    setup %{scope: scope, client: client} do
      {:ok, _} = PPImport.import_client(scope, client)
      giro = DomainFixtures.account_fixture(name: "Giro")
      [account_a | _] = Portfolios.list_accounts(scope)
      {:ok, _} = AccountRoles.set_role(scope, account_a, "budget_account:#{giro.id}")

      {:ok, _} =
        BudgetLink.switch_on(scope, %{
          category_id: DomainFixtures.category_fixture().id,
          start_date: ~D[2024-01-01]
        })

      assert Enum.any?(in_giro(giro), &(&1.amount == -100_550))
      %{giro: giro, account_a: account_a}
    end

    defp in_giro(giro),
      do:
        Repo.all(
          from t in Ledger.in_register(budget_scope()),
            where: t.account_id == ^giro.id,
            order_by: t.id
        )

    defp first_buy(client), do: Enum.find(client.transactions, &(&1.note == "Erstkauf"))

    test "a re-import changes a linked transaction's amount and keeps its category", c do
      [outflow | _] = Enum.filter(in_giro(c.giro), &(&1.amount == -100_550))
      other = DomainFixtures.category_fixture()
      {:ok, _} = Ledger.update_transaction(budget_scope(), outflow, %{category_id: other.id})

      buy = first_buy(c.client)

      changed =
        Enum.map(c.client.transactions, &if(&1 == buy, do: %{buy | amount: 100_600}, else: &1))

      {:ok, _} = PPImport.import_client(c.scope, %{c.client | transactions: changed})

      assert %{amount: -100_600, category_id: category_id} = Repo.reload!(outflow)
      assert category_id == other.id
    end

    test "a Depot transaction the file no longer has removes its linked transaction", c do
      before = in_giro(c.giro)
      buy = first_buy(c.client)

      {:ok, _} =
        PPImport.import_client(c.scope, %{
          c.client
          | transactions: List.delete(c.client.transactions, buy)
        })

      assert length(in_giro(c.giro)) == length(before) - 1
      refute Enum.any?(in_giro(c.giro), &(&1.amount == -100_550))
    end

    test "an account PP moves away from euros loses its budget role and its linked transactions",
         c do
      accounts =
        Enum.map(
          c.client.accounts,
          &if(&1.uuid == c.account_a.pp_uuid, do: %{&1 | currency: "USD"}, else: &1)
        )

      {:ok, _} = PPImport.import_client(c.scope, %{c.client | accounts: accounts})

      assert Repo.reload!(c.account_a).budget_account_id == nil
      assert in_giro(c.giro) == []
    end
  end

  test "links no transaction dated before the link's start date", %{scope: scope, client: client} do
    {:ok, _} = PPImport.import_client(scope, client)
    giro = DomainFixtures.account_fixture(name: "Giro")
    [account_a | _] = Portfolios.list_accounts(scope)
    {:ok, _} = AccountRoles.set_role(scope, account_a, "budget_account:#{giro.id}")

    {:ok, _} =
      BudgetLink.switch_on(scope, %{
        category_id: DomainFixtures.category_fixture().id,
        start_date: ~D[2024-01-03]
      })

    {:ok, _} = PPImport.import_client(scope, client)

    refute Enum.any?(in_giro(giro), &(&1.amount == -100_550))
  end

  test "keeps a security created in the Depot", %{scope: scope} do
    {:ok, _} = PPImport.run(scope, @sample)
    created = security_fixture(%{name: "Weltindex-ETF", symbol: "IUSQ.DE"})

    {:ok, summary} = PPImport.run(scope, @sample)

    assert summary.securities.deleted == 0
    assert Repo.get(Security, created.id)
  end

  test "keeps a security PP dropped while a user compares with it",
       %{scope: scope, client: client} do
    {:ok, _} = PPImport.import_client(scope, client)
    old_fund = Repo.get_by!(Security, name: "Altfonds ohne ISIN")
    {:ok, _setting} = Settings.update_benchmark(scope, old_fund.id)

    dropped = Enum.reject(client.securities, &(&1.isin == nil))
    {:ok, summary} = PPImport.import_client(scope, %{client | securities: dropped})

    assert summary.securities.deleted == 0
    assert Repo.get(Security, old_fund.id)
  end

  test "keeps a quote feed set in the Depot", %{scope: scope} do
    {:ok, _} = PPImport.run(scope, @sample)

    {:ok, _} =
      Securities.update_quote_feed(scope, security("US0378331005"), %{
        quote_feed: :yahoo,
        symbol: "APC.DE"
      })

    {:ok, summary} = PPImport.run(scope, @sample)

    assert import_unchanged?(summary)
    assert %{quote_feed: :yahoo, symbol: "APC.DE"} = security("US0378331005")
  end

  test "keeps a latest quote fetched since, but not an older one", %{scope: scope} do
    {:ok, _} = PPImport.run(scope, @sample)

    world =
      security("IE00B4L5Y983")
      |> change(
        latest_date: ~D[2026-10-09],
        latest_close: 1,
        latest_at: ~U[2026-10-09 15:35:00.000000Z]
      )
      |> Repo.update!()

    {:ok, summary} = PPImport.run(scope, @sample)

    assert import_unchanged?(summary)
    assert %{latest_date: ~D[2026-10-09], latest_close: 1} = security("IE00B4L5Y983")

    world |> change(latest_date: ~D[2024-01-01]) |> Repo.update!()

    {:ok, _summary} = PPImport.run(scope, @sample)

    assert %{latest_date: ~D[2024-03-04], latest_close: 9_095_000_000, latest_at: nil} =
             security("IE00B4L5Y983")
  end

  test "PP prices win over fetched ones on the same day, others stay", %{scope: scope} do
    {:ok, _} = PPImport.run(scope, @sample)
    world = security("IE00B4L5Y983")

    Repo.update_all(
      from(p in Price, where: p.security_id == ^world.id and p.date == ^~D[2024-01-02]),
      set: [close: 1, source: :yahoo]
    )

    Repo.insert!(%Price{
      security_id: world.id,
      date: ~D[2024-03-05],
      close: 9_100_000_000,
      source: :yahoo
    })

    {:ok, summary} = PPImport.run(scope, @sample)

    assert summary.prices == %{created: 0, updated: 1, deleted: 0}
    prices = Map.new(Securities.list_prices(scope, world), &{&1.date, {&1.close, &1.source}})
    assert prices[~D[2024-01-02]] == {8_510_000_000, :pp}
    assert prices[~D[2024-03-05]] == {9_100_000_000, :yahoo}
  end

  test "keeps transactions entered in the Depot", %{scope: scope} do
    {:ok, _} = PPImport.run(scope, @sample)
    refute Portfolios.own_transactions?(scope)

    [account | _] = Portfolios.list_accounts(scope)

    Repo.insert!(%Transaction{
      user_id: scope.user.id,
      type: :deposit,
      date_time: ~N[2024-04-01 10:00:00],
      account_id: account.id,
      amount: 5_000,
      currency: "EUR",
      source: :manual
    })

    {:ok, summary} = PPImport.run(scope, @sample)

    assert import_unchanged?(summary)
    assert Portfolios.own_transactions?(scope)
    assert length(Portfolios.list_transactions(scope)) == 22
  end

  test "a second user shares securities but not portfolios", %{scope: scope} do
    other = user_scope_fixture()
    {:ok, _} = PPImport.run(scope, @sample)
    {:ok, summary} = PPImport.run(other, @sample)

    # Matched by ISIN; the security without an ISIN cannot be matched.
    assert summary.securities == %{created: 1, updated: 0, deleted: 0}
    assert length(Securities.list_securities(scope)) == 5

    assert length(Portfolios.list_portfolios(scope)) == 2
    assert length(Portfolios.list_portfolios(other)) == 2

    assert MapSet.disjoint?(
             ids(Portfolios.list_portfolios(scope)),
             ids(Portfolios.list_portfolios(other))
           )

    # Removing it from one user's file keeps a security the other user still has.
    {:ok, client} = Reader.read(@sample)
    world = Enum.find(client.securities, &(&1.isin == "IE00B4L5Y983"))

    without_world = %{
      client
      | securities: List.delete(client.securities, world),
        transactions: [],
        plans: [],
        taxonomies: []
    }

    {:ok, summary} = PPImport.import_client(other, without_world)

    assert summary.securities.deleted == 0
    assert security("IE00B4L5Y983")
  end

  test "keeps an account PP dropped while transactions entered in the Depot use it",
       %{scope: scope, client: client} do
    {:ok, _} = PPImport.import_client(scope, client)
    usd = Enum.find(Portfolios.list_accounts(scope), &(&1.currency == "USD"))

    Repo.insert!(%Transaction{
      user_id: scope.user.id,
      type: :removal,
      date_time: ~N[2024-04-01 10:00:00],
      account_id: usd.id,
      amount: 1_000,
      currency: "USD",
      source: :manual
    })

    pp_usd = Enum.find(client.accounts, &(&1.uuid == usd.pp_uuid))

    without_usd = %{
      client
      | accounts: List.delete(client.accounts, pp_usd),
        transactions: Enum.reject(client.transactions, &(&1.account == pp_usd.uuid))
    }

    {:ok, summary} = PPImport.import_client(scope, without_usd)

    assert summary.accounts == %{created: 0, updated: 1, deleted: 0}
    assert %{pp_uuid: nil} = Repo.reload!(usd)
    assert Portfolios.own_transactions?(scope)
  end

  test "opens an account for each imported portfolio and closes it once PP dropped the portfolio",
       %{
         scope: scope,
         client: client
       } do
    {:ok, _} = PPImport.import_client(scope, client)
    portfolios = Portfolios.list_portfolios(scope)
    accounts = Enum.map(portfolios, &Repo.get!(Ledger.Account, &1.budget_account_id))

    assert Enum.map(accounts, &{&1.name, &1.fed_by, &1.closed}) ==
             Enum.map(portfolios, &{&1.name, :portfolio, false})

    {:ok, summary} =
      PPImport.import_client(scope, %{client | portfolios: [], transactions: [], plans: []})

    assert summary.portfolios.deleted == 2
    assert Enum.all?(accounts, &Repo.reload!(&1).closed)
    refute BudgetFeed.in_use?(budget_scope())
  end

  test "keeps a security PP recreated under a new UUID", %{scope: scope, client: client} do
    {:ok, _} = PPImport.import_client(scope, client)
    em = security("IE00BTJRMP35")
    {:ok, _} = Securities.update_quote_feed(scope, em, %{quote_feed: :manual})

    old_uuid = Enum.find(client.securities, &(&1.isin == "IE00BTJRMP35")).uuid

    {:ok, summary} =
      PPImport.import_client(scope, replace(client, old_uuid, Ecto.UUID.generate()))

    assert summary.securities == %{created: 0, updated: 0, deleted: 0}
    assert %{id: id, quote_feed: :manual} = security("IE00BTJRMP35")
    assert id == em.id
  end

  defp replace(term, old, new) when is_map(term) and not is_struct(term),
    do: Map.new(term, fn {k, v} -> {k, replace(v, old, new)} end)

  defp replace(term, old, new) when is_list(term), do: Enum.map(term, &replace(&1, old, new))
  defp replace(old, old, new), do: new
  defp replace(term, _old, _new), do: term

  test "does not match securities by an empty ISIN", %{scope: scope, client: client} do
    other = user_scope_fixture()
    [first, second | _] = client.securities

    {:ok, _} = PPImport.import_client(scope, %{client | securities: [%{first | isin: ""}]})
    {:ok, summary} = PPImport.import_client(other, %{client | securities: [%{second | isin: ""}]})

    assert summary.securities.created == 1
  end

  test "imports an account whose name PP left empty", %{scope: scope} do
    # proto3 leaves out empty strings: the account has only its UUID.
    {:ok, client} = Reader.parse(zip("PPPBV1" <> <<0x1A, 3, 0x0A, 1, "a">>))

    assert {:ok, %{accounts: %{created: 1}}} = PPImport.import_client(scope, client)
  end

  defp zip(data) do
    {:ok, {_name, bin}} = :zip.create(~c"x.zip", [{~c"data.portfolio", data}], [:memory])
    bin
  end

  defp ids(records), do: MapSet.new(records, & &1.id)

  describe "files that cannot be imported" do
    @describetag :tmp_dir

    test "rejects files that are not PP files", %{scope: scope, tmp_dir: dir} do
      path = Path.join(dir, "notes.portfolio")
      File.write!(path, "not a zip")
      assert PPImport.run(scope, path) == {:error, :not_a_pp_file}
    end

    test "rejects PP's XML format", %{tmp_dir: dir} do
      path = Path.join(dir, "xml.portfolio")
      {:ok, _} = :zip.create(String.to_charlist(path), [{~c"data.xml", "<client/>"}])
      assert Reader.read(path) == {:error, :xml_format}
    end

    test "rejects broken protobuf data", %{tmp_dir: dir} do
      path = Path.join(dir, "broken.portfolio")

      {:ok, _} =
        :zip.create(String.to_charlist(path), [{~c"data.portfolio", "PPPBV1" <> <<0x12, 9, "x">>}])

      assert Reader.read(path) == {:error, :malformed}
    end

    test "rejects an entry that unpacks larger than it says" do
      content = "PPPBV1" <> :binary.copy(<<0>>, 2_000_000)
      {:ok, {_, zip}} = :zip.create(~c"x.zip", [{~c"data.portfolio", content}], [:memory])

      lying =
        :binary.replace(zip, <<byte_size(content)::little-32>>, <<10::little-32>>, [:global])

      assert {:ok, [_comment, {:zip_file, _, info, _, _, _}]} = :zip.list_dir(lying)
      assert elem(info, 1) == 10

      assert Reader.parse(lying, max_unpacked: 1_000_000) == {:error, :too_large}
    end

    test "rejects an entry larger than allowed" do
      content = "PPPBV1" <> :binary.copy(<<0>>, 2_000_000)
      {:ok, {_, zip}} = :zip.create(~c"x.zip", [{~c"data.portfolio", content}], [:memory])

      assert Reader.parse(zip, max_unpacked: 1_000_000) == {:error, :too_large}
    end

    test "reads stored entries and rejects damaged ones" do
      {:ok, {_, stored}} =
        :zip.create(~c"x.zip", [{~c"data.xml", "<client/>"}], [:memory, uncompress: :all])

      assert Reader.parse(stored) == {:error, :xml_format}

      content = "PPPBV1" <> :binary.copy("abc", 10_000)
      {:ok, {_, zip}} = :zip.create(~c"x.zip", [{~c"data.portfolio", content}], [:memory])
      [{:zip_file, _, _, _, offset, size}] = zip |> :zip.list_dir() |> elem(1) |> tl()
      data_start = offset + 30 + byte_size("data.portfolio")

      damaged =
        binary_part(zip, 0, data_start) <>
          :binary.copy(<<0xFF>>, size) <>
          binary_part(zip, data_start + size, byte_size(zip) - data_start - size)

      assert Reader.parse(damaged) == {:error, :not_a_pp_file}
    end
  end
end

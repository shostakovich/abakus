defmodule Abakus.Depot.ImportTest do
  use Abakus.DataCase

  import Swoosh.TestAssertions

  alias Abakus.Depot.{Import, Portfolios, PortfoliosFixtures, Receipts}
  alias Abakus.Depot.{Securities, Settings, Taxonomies}

  alias Abakus.Depot.Securities.{AttributeType, Composition, DivvyDiaryDividend, PPSecurityLink}
  alias Abakus.ExchangeRates
  alias Abakus.Repo
  alias Abakus.Users
  alias Abakus.Users.Scope

  @moduletag :tmp_dir

  @purchase "a7e1f6e59756f1cb2440ea200495f4e02025aa5f6523d34d8178bb1c9e840e37"
  @savings_plan "1705d84339a3fafbd3dd623cc6d421ba21871df5d18731805d638653034fdfda"

  setup %{tmp_dir: dir} do
    {:ok, _owner} = Users.create_user(%{email: "owner@example.com"})
    %{path: PortfoliosFixtures.old_app_file!(dir)}
  end

  defp import!(path) do
    {:ok, report} = Import.run(Scope.system(), path)
    report
  end

  defp scope(email), do: Scope.for_user(Users.get_user_by_email(email))

  test "keeps portfolios, accounts and transactions with their ids, matching users by email", %{
    path: path
  } do
    {:ok, anna} = Users.create_user(%{email: "anna@example.com"})

    report = import!(path)

    assert report.matched == ["anna@example.com"]
    assert report.created == ["ben@example.com"]
    assert {report.rows["transactions"], report.rows["receipts"]} == {5, 3}
    assert report.receipt_files == 2
    assert_no_email_sent()

    scope = Scope.for_user(anna)

    assert [%{id: 1, name: "Langfristig", reference_account_id: 1, depot_number: "4472"}] =
             Portfolios.list_portfolios(scope)

    assert [%{id: 1, name: "Verrechnung", currency: "EUR"}] = Portfolios.list_accounts(scope)

    assert for(t <- Portfolios.list_transactions(scope), do: {t.id, t.type, t.amount}) ==
             [{5, :deposit, 500_000}, {9, :buy, 5000}, {6, :buy, 112_500}, {8, :dividend, 1234}]

    dividend = Portfolios.get_transaction(scope, 8)

    assert {dividend.ex_date, dividend.note, dividend.source} ==
             {~N[2026-09-25 00:00:00], "Q3", :manual}

    assert [%{type: :tax, amount: 300}] = dividend.units
    assert Portfolios.any?(anna)

    assert %{confirmed_at: nil, budget_owner: false} = Users.get_user_by_email("ben@example.com")
    assert Users.list_passkeys(anna) == []
  end

  test "keeps each user's receipts with their files and the inbox", %{path: path} do
    import!(path)
    anna = scope("anna@example.com")

    assert %{id: 6, receipt_id: 1, source: :receipt} = Portfolios.get_transaction(anna, 6)
    booked = Portfolios.get_receipt(anna, 1)

    assert {booked.status, booked.filename, booked.sha256} ==
             {:booked, "Kauf VWCE.pdf", @purchase}

    assert File.read!(Portfolios.receipt_file(booked)) =~ "Abrechnung Kauf"

    assert [waiting] = Receipts.list_inbox(anna)
    assert {waiting.id, waiting.status, waiting.paperless_id} == {2, :ready, 17}
    assert {waiting.fields.kind, waiting.fields.amount} == {:purchase, Decimal.new("1125.00")}
    assert File.read!(Portfolios.receipt_file(waiting)) =~ "Sparplan Oktober"
  end

  test "keeps the separation between users", %{path: path} do
    import!(path)
    anna = scope("anna@example.com")
    ben = scope("ben@example.com")

    assert [%{id: 3, name: "Bens Depot"}] = Portfolios.list_portfolios(ben)
    assert [%{id: 2}] = Portfolios.list_accounts(ben)

    assert [%{id: 7, receipt_id: 3, units: [_gross, _fee]} = purchase] =
             Portfolios.list_transactions(ben)

    assert Enum.find(purchase.units, &(&1.type == :gross_value)).fx_rate ==
             Decimal.from_float(1.0815)

    assert %{user_id: user_id, sha256: @purchase} = Portfolios.get_receipt(ben, 3)
    assert user_id == ben.user.id
    assert Receipts.list_inbox(ben) == []

    assert Portfolios.get_transaction(ben, 6) == nil
    assert Portfolios.get_receipt(ben, 1) == nil
    assert Portfolios.get_receipt(anna, 3) == nil
    assert Portfolios.list_savings_plans(ben) == []
    assert Taxonomies.list_taxonomies(ben) == []
  end

  test "keeps savings plans, taxonomies and the Depot settings per user", %{path: path} do
    import!(path)
    anna = scope("anna@example.com")

    assert [%{id: 2, name: "Sparplan MSCI World", transactions: [%{id: 9}]}] =
             Portfolios.list_savings_plans(anna)

    assert [%{name: "Anlageklassen", dimensions: ["Anlageklasse"], classifications: classes}] =
             Taxonomies.list_taxonomies(anna)

    assert for(c <- classes, do: {c.id, c.parent_id, length(c.assignments)}) ==
             [{5, 7, 1}, {7, nil, 1}]

    assert %{benchmark_id: 2, paperless_url: "https://paperless.example.com"} =
             settings = Settings.get_settings(anna)

    assert {settings.paperless_token, settings.paperless_tag, settings.paperless_polled_at} ==
             {"token-anna", "Depot", ~U[2026-10-12 09:00:00.000000Z]}

    assert Settings.get_settings(scope("ben@example.com")).id == nil
  end

  test "keeps the shared securities, prices, rates and market data", %{path: path} do
    ExchangeRates.store([{"USD", ~D[2026-10-12], Decimal.new("1.0790")}])

    import!(path)
    anna = scope("anna@example.com")

    assert for(s <- Securities.list_securities(anna), do: s.id) |> Enum.sort() == [1, 2, 4]
    apple = Securities.get_security(scope("ben@example.com"), 4)

    assert {apple.attributes, apple.source, apple.note} ==
             {%{"logo" => "apple.png"}, :manual, "Einzelaktie"}

    assert length(Securities.list_prices(anna, Securities.get_security(anna, 1))) == 2

    assert ExchangeRates.list_rates_since(["USD"], ~D[2026-10-09]) == [
             {"USD", ~D[2026-10-09], Decimal.new("1.0823")},
             {"USD", ~D[2026-10-12], Decimal.new("1.0791")}
           ]

    assert [%{security_id: 1, pp_uuid: "pp-security-1"}, _second] = Repo.all(PPSecurityLink)
    assert [%{pp_id: "logo"}] = Repo.all(AttributeType)
    assert [%{security_id: 1, countries: %{"US" => 6200}}] = Repo.all(Composition)
    assert [%{security_id: 4, per_share: 26}] = Repo.all(DivvyDiaryDividend)
  end

  test "refuses a missing file, missing receipt files and a Depot that holds data already", %{
    path: path,
    tmp_dir: dir
  } do
    assert Import.run(Scope.system(), path <> ".missing") ==
             {:error, "#{path}.missing is not a file"}

    missing = Path.join([dir, "receipts", "#{@savings_plan}.pdf"])
    File.rm!(missing)
    assert Import.run(Scope.system(), path) == {:error, "receipt file missing: #{missing}"}
    refute Users.get_user_by_email("ben@example.com")

    complete = PortfoliosFixtures.old_app_file!(Path.join(dir, "complete"))
    import!(complete)

    assert Import.run(Scope.system(), complete) ==
             {:error, "the Depot holds data already (depot_securities)"}
  end

  test "refuses an Abakus without users, whose budget owner it would make", %{path: path} do
    Repo.delete_all(Users.User)

    assert {:error, message} = Import.run(Scope.system(), path)
    assert message =~ "invite the budget owner first"
    refute Repo.exists?(Users.User)
    refute Repo.exists?(Abakus.Depot.Securities.Security)
  end

  test "rolls back on a damaged receipt file", %{path: path, tmp_dir: dir} do
    damaged = Path.join([dir, "receipts", "#{@savings_plan}.pdf"])
    File.write!(damaged, "%PDF-1.4\nanders\n%%EOF\n")

    assert Import.run(Scope.system(), path) == {:error, "receipt file damaged: #{damaged}"}

    refute Users.get_user_by_email("ben@example.com")
    refute Repo.exists?(Abakus.Depot.Securities.Security)
    refute Repo.exists?(Abakus.Depot.Portfolios.Receipt)
  end
end

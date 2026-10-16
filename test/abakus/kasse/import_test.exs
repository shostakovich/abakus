defmodule Abakus.Kasse.ImportTest do
  use Abakus.DataCase

  import Swoosh.TestAssertions

  alias Abakus.ExchangeRates
  alias Abakus.Kasse.{Activities, Categories, Expenses, Import, Participants, Recurring, Settings}
  alias Abakus.Kasse.FakeYnab
  alias Abakus.Kasse.Ynab.{Connections, Sync, Transactions}
  alias Abakus.Repo
  alias Abakus.Users

  @moduletag :tmp_dir

  @emails %{
    "anna" => "anna@example.com",
    "Ben" => "ben@example.com",
    "Cleo" => "cleo@example.com"
  }

  setup %{tmp_dir: dir} do
    {:ok, _owner} = Users.create_user(%{email: "owner@example.com"})
    %{path: Abakus.KasseFixtures.old_app_file!(dir)}
  end

  defp import!(path, emails \\ @emails) do
    {:ok, report} = Import.run(path, emails)
    report
  end

  test "keeps the ids of people, categories, expenses and rules, matching users by email", %{
    path: path
  } do
    {:ok, anna} = Users.create_user(%{email: "anna@example.com"})

    report = import!(path)

    assert report.matched == ["anna@example.com"]
    assert report.created == ["ben@example.com", "cleo@example.com"]
    assert report.rows["expenses"] == 5
    assert_no_email_sent()

    assert [{1, "Anna", nil}, {2, "Ben", nil}, {5, "Cleo", %DateTime{}}] =
             for(p <- Participants.list_participants(:all), do: {p.id, p.name, p.archived_at})

    assert Participants.for_user(anna).id == 1
    assert %{confirmed_at: nil} = Users.get_user_by_email("ben@example.com")
    assert Participants.for_user(Users.get_user_by_email("ben@example.com")).id == 2

    assert for(c <- Categories.list_categories(:all), do: {c.id, c.name}) ==
             [
               {1, "Lebensmittel"},
               {2, "Restaurant"},
               {4, "Miete & Nebenkosten"},
               {11, "Katze"},
               {10, "Sonstiges"}
             ]

    assert Settings.group_name() == "WG Sonnenblick"
    assert Enum.map(Expenses.list_expenses(), & &1.id) == [15, 12, 9, 7]
    assert Expenses.get_expense!(13).deleted_at
    assert Expenses.next_id() == 16
  end

  test "keeps shares, foreign amounts and recurring rules", %{path: path} do
    import!(path)

    diner = Expenses.get_expense!(15)

    assert {diner.amount_cents, diner.original_amount, diner.original_currency} ==
             {4450, 5000, "USD"}

    assert {diner.fx_rate, diner.fx_source, diner.split_mode} == {1.1236, :ecb, :shares}

    assert for(s <- diner.shares, do: {s.participant_id, s.weight, s.amount_cents}) ==
             [{1, 2, 2967}, {2, 1, 1483}]

    assert Expenses.get_expense!(12).reimbursement

    assert [rule] = Recurring.list_rules()

    assert {rule.id, rule.frequency, rule.next_date, rule.created_by_id} ==
             {3, :monthly, ~D[2026-11-01], 1}

    assert rule.template.split_mode == :percent

    assert for(p <- rule.template.parts, do: {p.participant_id, p.weight}) == [
             {1, 6000},
             {2, 4000}
           ]

    assert Expenses.get_expense!(9).recurring_expense_id == 3

    assert [%{currency: "USD", date: ~D[2026-10-01], rate: rate}] =
             ExchangeRates.list_manual_rates()

    assert Decimal.equal?(rate, "1.15")
    assert ExchangeRates.ecb_stats().count == 0
  end

  test "keeps the activity log with its authors and changes", %{path: path} do
    import!(path)

    entries = Activities.list_activities()
    assert Enum.map(entries, & &1.id) == [32, 31, 30, 1]

    [update, deletion | _] = entries
    assert {update.actor.name, update.action, update.expense_id} == {"Anna", :expense_updated, 15}
    assert [%{field: "Notiz", old: "", new: "Urlaub"}] = update.details.changes
    assert {deletion.actor.name, deletion.details.title} == {"Ben", "Kino"}
    assert List.last(entries).details.text == "Person „Anna“ hinzugefügt"
  end

  test "keeps the YNAB state, so the next sync has nothing to do", %{path: path} do
    import!(path)
    fake = FakeYnab.start()

    connection = Connections.get(1)

    assert {connection.token, connection.plan_id, connection.account_id} ==
             {FakeYnab.token(), FakeYnab.plan(), FakeYnab.account()}

    assert connection.start_date == ~D[2026-09-01]
    assert Connections.category_mapping(1) == %{1 => "cat-food", 4 => "cat-rent"}

    assert for(t <- Transactions.list(1), do: {t.expense_id, t.ynab_transaction_id}) ==
             [{7, "ynab-7"}, {9, "ynab-9"}, {15, "ynab-15"}]

    outcome = Sync.sync_person(1, true, now: ~U[2026-10-15 12:00:00Z])

    assert {outcome.error, outcome.result.created, outcome.result.updated} == {nil, 0, 0}
    assert FakeYnab.take_requests(fake) == []
  end

  test "refuses a Kasse that holds data already, and missing or unknown people", %{path: path} do
    assert Import.run(path, Map.delete(@emails, "Cleo")) == {:error, "no email address for Cleo"}

    assert Import.run(path, Map.put(@emails, "Dora", "dora@example.com")) ==
             {:error, "no person named dora"}

    assert Import.run(path, %{@emails | "Ben" => "ANNA@example.com"}) ==
             {:error, "two people with the same email address"}

    assert {:error, "#{path}.missing is not a file"} == Import.run(path <> ".missing", @emails)

    import!(path)

    assert Import.run(path, @emails) ==
             {:error, "the Kasse holds data already (kasse_participants)"}

    refute Repo.exists?(Abakus.Users.User |> where(email: "dora@example.com"))
  end

  test "refuses an Abakus without users, whose budget owner it would make", %{path: path} do
    Repo.delete_all(Users.User)

    assert {:error, message} = Import.run(path, @emails)
    assert message =~ "invite the budget owner first"
    refute Repo.exists?(Users.User)
    assert Participants.list_participants(:all) == []
  end
end

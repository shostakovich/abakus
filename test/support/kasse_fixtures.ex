defmodule Abakus.KasseFixtures do
  @moduledoc """
  Test data of the Kasse: Anna, Ben and Cleo with the seeded categories (Lebensmittel first, Restaurant
  second), and expense inputs among them. Each person is a user; Anna, the first, owns the budget unless a user
  was there before.
  """

  alias Abakus.Kasse.{Categories, Expenses, Participants}

  def household do
    [anna, ben, cleo] =
      for name <- ~w(Anna Ben Cleo) do
        participant = person!(name)
        participant.id
      end

    [food, restaurant | _] = Categories.list_categories()
    %{anna: anna, ben: ben, cleo: cleo, food: food.id, restaurant: restaurant.id}
  end

  @doc "A person with the user `<name>@example.com`, added by `actor_id`."
  def person!(name, actor_id \\ nil) do
    email = (name |> String.trim() |> String.downcase()) <> "@example.com"
    {:ok, participant} = Participants.create_participant(actor_id, %{name: name, email: email})
    participant
  end

  @doc "An equal split of `cents` among `people`, in the category Lebensmittel."
  def equal(household, title, cents, date, payer, people) do
    %{
      title: title,
      date: Date.from_iso8601!(date),
      category_id: household.food,
      paid_by_id: payer,
      amount_cents: cents,
      split_mode: :equal,
      parts: Enum.map(people, &%{participant_id: &1, weight: 0})
    }
  end

  @doc "A reimbursement of `cents` from `payer` to `recipient`."
  def reimbursement(cents, date, payer, recipient) do
    %{
      title: "Rückzahlung",
      date: Date.from_iso8601!(date),
      paid_by_id: payer,
      amount_cents: cents,
      reimbursement: true,
      parts: [%{participant_id: recipient, weight: 0}]
    }
  end

  @doc "`minor` units of `currency` at `rate`, an ECB rate, split equally among `people`."
  def foreign(household, title, minor, currency, rate, date, payer, people) do
    household
    |> equal(title, 0, date, payer, people)
    |> Map.merge(%{
      original_currency: currency,
      original_amount: minor,
      fx_rate: rate,
      fx_source: :ecb
    })
  end

  @old_app Path.expand("fixtures/kasse/old_app.sql", __DIR__)

  @doc "The former shared-expenses app's database file with data in every table, written into `dir`."
  def old_app_file!(dir) do
    path = Path.join(dir, "old.sqlite3")
    {:ok, db} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(db, File.read!(@old_app))
    :ok = Exqlite.Sqlite3.close(db)
    path
  end

  def create!(attrs, actor_id \\ nil) do
    {:ok, expense} = Expenses.create_expense(actor_id, attrs)
    expense
  end
end

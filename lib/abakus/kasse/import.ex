defmodule Abakus.Kasse.Import do
  @moduledoc """
  Brings the database file of the former shared-expenses app into the empty Kasse, once, keeping every id: people,
  categories (replacing the seeded ones), the group's name, recurring expenses, expenses with their shares, the
  activity log, manual exchange rates and each person's YNAB connection, category mapping and synced transactions.

  Each person becomes the user with the email address given for their name: an existing user, or a new one who gets
  no mail and asks for a sign-in link on the sign-in page. Abakus needs a user first, the budget owner.
  """

  alias Abakus.ExchangeRates.ExchangeRate
  alias Abakus.Kasse.Access
  alias Abakus.Repo
  alias Abakus.Users
  alias Abakus.Users.{Scope, User}
  alias Exqlite.Sqlite3

  # In the order of their foreign keys; the old app's tables lack the prefix.
  @tables ~w(categories settings participants recurring_expenses expenses expense_shares activities fx_rates
             ynab_connections ynab_category_mappings ynab_transactions)
  @guarded ~w(participants expenses recurring_expenses activities)
  @replaced ~w(categories settings)
  @chunk 200

  @doc """
  Imports the file at `path` with the system's scope; `emails` gives each person's email address by name
  (case-insensitive). Returns the rows imported per table and the users matched and created, by email.
  """
  def run(%Scope{} = scope, path, emails) do
    Access.system!(scope)

    with {:ok, data} <- read(path),
         {:ok, emails} <- emails_by_id(data["participants"], emails) do
      Repo.transact(fn -> write_once(data, emails) end)
    end
  end

  defp write_once(data, emails) do
    with :ok <- check_users(),
         :ok <- check_empty() do
      {users, report} = users(emails)
      write(data, users)
      {:ok, Map.put(report, :rows, Map.new(data, fn {table, rows} -> {table, length(rows)} end))}
    end
  end

  defp read(path) do
    if File.regular?(path) do
      {:ok, db} = Sqlite3.open(path, mode: :readonly)

      try do
        Enum.reduce_while(@tables, {:ok, %{}}, fn table, {:ok, data} ->
          case rows(db, table) do
            {:ok, rows} -> {:cont, {:ok, Map.put(data, table, rows)}}
            {:error, message} -> {:halt, {:error, "#{table}: #{message}"}}
          end
        end)
      after
        Sqlite3.close(db)
      end
    else
      {:error, "#{path} is not a file"}
    end
  end

  defp rows(db, table) do
    columns = columns(table) -- ["user_id"]
    sql = "SELECT #{Enum.map_join(columns, ", ", &~s("#{&1}"))} FROM \"#{table}\""

    with {:ok, statement} <- Sqlite3.prepare(db, sql) do
      try do
        with {:ok, rows} <- Sqlite3.fetch_all(db, statement),
             do: {:ok, Enum.map(rows, &Map.new(Enum.zip(columns, &1)))}
      after
        Sqlite3.release(db, statement)
      end
    end
  end

  defp columns("fx_rates"), do: ~w(currency source date rate)

  defp columns(table) do
    %{rows: rows} = Repo.query!("SELECT name FROM pragma_table_info(?)", ["kasse_" <> table])
    List.flatten(rows)
  end

  defp emails_by_id(participants, emails) do
    given = Map.new(emails, fn {name, email} -> {String.downcase(name), email} end)
    names = MapSet.new(participants, &String.downcase(&1["name"]))
    by_id = Map.new(participants, &{&1["id"], given[String.downcase(&1["name"])]})

    cond do
      missing = Enum.find(participants, &is_nil(by_id[&1["id"]])) ->
        {:error, "no email address for #{missing["name"]}"}

      unknown = Enum.find(Map.keys(given), &(not MapSet.member?(names, &1))) ->
        {:error, "no person named #{unknown}"}

      length(Enum.uniq_by(Map.values(by_id), &User.normalize_email/1)) < map_size(by_id) ->
        {:error, "two people with the same email address"}

      true ->
        {:ok, by_id}
    end
  end

  # The first user owns the budget, which must not be someone the import creates.
  defp check_users do
    if Repo.exists?(User),
      do: :ok,
      else:
        {:error,
         "Abakus has no users yet; invite the budget owner first (Abakus.Release.invite/1)"}
  end

  defp check_empty do
    case Enum.find(@guarded, &Repo.exists?("kasse_" <> &1)) do
      nil -> :ok
      table -> {:error, "the Kasse holds data already (kasse_#{table})"}
    end
  end

  defp users(emails) do
    found = Map.new(emails, fn {id, email} -> {id, user(email)} end)
    users = Map.new(found, fn {id, {_kind, user}} -> {id, user.id} end)
    by_kind = found |> Map.values() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1).email)

    {users,
     %{matched: Enum.sort(by_kind[:matched] || []), created: Enum.sort(by_kind[:created] || [])}}
  end

  defp user(email) do
    case Users.get_user_by_email(email) do
      nil -> {:created, create_user!(email)}
      user -> {:matched, user}
    end
  end

  defp create_user!(email) do
    case Users.create_user(%{email: email}) do
      {:ok, user} -> user
      {:error, changeset} -> Repo.rollback("#{email}: #{inspect(changeset.errors)}")
    end
  end

  defp write(data, users) do
    Enum.each(@replaced, &Repo.delete_all("kasse_" <> &1))

    for table <- @tables do
      data[table]
      |> Enum.map(&row(table, &1, users))
      |> Enum.chunk_every(@chunk)
      |> Enum.each(&insert(table, &1))
    end
  end

  defp row("participants", row, users), do: row |> atoms() |> Map.put(:user_id, users[row["id"]])
  defp row(_table, row, _users), do: atoms(row)

  defp atoms(row), do: Map.new(row, fn {column, value} -> {String.to_atom(column), value} end)

  # The old app's ECB rates are left to the shared daily load.
  defp insert("fx_rates", rows) do
    Repo.insert_all(
      ExchangeRate,
      for %{source: "manual"} = row <- rows do
        %{
          currency: row.currency,
          date: Date.from_iso8601!(row.date),
          source: :manual,
          rate: Decimal.from_float(row.rate)
        }
      end,
      on_conflict: {:replace, [:rate]},
      conflict_target: [:currency, :source, :date]
    )
  end

  defp insert(table, rows), do: Repo.insert_all("kasse_" <> table, rows)
end

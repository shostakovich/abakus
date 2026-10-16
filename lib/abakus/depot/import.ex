defmodule Abakus.Depot.Import do
  @moduledoc """
  Brings the database file of the former portfolio app into the empty Depot, once, keeping every id: the shared
  securities with their prices, exchange rates and market data, each user's accounts, portfolios, transactions,
  savings plans, taxonomies and receipts, whose files come from the `receipts` folder next to the database file, and
  each user's benchmark and Paperless as their Depot settings.

  Each user becomes the user with the same email address: an existing one, or a new one who gets no mail and asks for
  a sign-in link on the sign-in page. Abakus needs a user first, the budget owner. Sessions and passkeys stay behind,
  as passkeys belong to the old address.
  """

  alias Abakus.Depot.Portfolios
  alias Abakus.Repo
  alias Abakus.Users
  alias Abakus.Users.User
  alias Exqlite.Sqlite3

  # The old app's tables lack the prefix. Its job runs stay behind: they tell when its own jobs last ran.
  @tables ~w(securities attribute_types pp_security_links prices accounts portfolios receipts transactions
             transaction_units savings_plans savings_plan_transactions taxonomies classifications assignments
             compositions divvy_diary_dividends exchange_rates)
  @per_user ~w(pp_security_links accounts portfolios receipts transactions savings_plans taxonomies)
  @guarded @tables -- ["exchange_rates"]
  @settings ~w(benchmark_id paperless_url paperless_token paperless_tag paperless_polled_at)
  @user_columns ~w(id email inserted_at updated_at) ++ @settings
  @chunk 200

  @doc """
  Imports the file at `path`. Returns the rows imported per table, the users matched and created, by email, and the
  number of receipt files.
  """
  def run(path) do
    with {:ok, data} <- read(path),
         :ok <- check_receipt_files(data["receipts"], receipts_folder(path)) do
      Repo.transact(fn -> write_once(data, receipts_folder(path)) end)
    end
  end

  defp receipts_folder(path), do: Path.join(Path.dirname(path), "receipts")

  defp write_once(data, receipts_folder) do
    with :ok <- check_users(),
         :ok <- check_empty() do
      # A classification may come in a later chunk than its children.
      Repo.query!("PRAGMA defer_foreign_keys = ON")

      {users, report} = users(data["users"])
      write(data, users)
      write_settings(data["users"], users)

      {:ok,
       Map.merge(report, %{
         rows: Map.new(@tables, &{&1, length(data[&1])}),
         receipt_files: copy_receipt_files(data["receipts"], receipts_folder)
       })}
    end
  end

  defp read(path) do
    if File.regular?(path) do
      {:ok, db} = Sqlite3.open(path, mode: :readonly)

      try do
        Enum.reduce_while(sources(), {:ok, %{}}, fn {table, columns}, {:ok, data} ->
          case rows(db, table, columns) do
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

  defp sources, do: [{"users", @user_columns} | Enum.map(@tables, &{&1, columns(&1)})]

  defp rows(db, table, columns) do
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

  # Exchange rates get new ids, as the Depot may have fetched some already; the old app lacks the budget's columns.
  defp columns("exchange_rates"), do: table_columns("exchange_rates") -- ["id"]
  defp columns("portfolios"), do: table_columns("portfolios") -- ["budget_account_id"]

  defp columns("accounts"),
    do: table_columns("accounts") -- ["budget_account_id", "cash_of_portfolio_id", "no_role"]

  defp columns(table), do: table_columns(table)

  defp table_columns(table) do
    %{rows: rows} = Repo.query!("SELECT name FROM pragma_table_info(?)", ["depot_" <> table])
    List.flatten(rows)
  end

  defp check_receipt_files(receipts, folder) do
    case Enum.find(receipts, &(not File.regular?(receipt_source(folder, &1["sha256"])))) do
      nil -> :ok
      receipt -> {:error, "receipt file missing: #{receipt_source(folder, receipt["sha256"])}"}
    end
  end

  defp receipt_source(folder, sha256), do: Path.join(folder, "#{sha256}.pdf")

  # The first user owns the budget, which must not be someone the import creates.
  defp check_users do
    if Repo.exists?(User),
      do: :ok,
      else:
        {:error,
         "Abakus has no users yet; invite the budget owner first (Abakus.Release.invite/1)"}
  end

  defp check_empty do
    case Enum.find(@guarded, &Repo.exists?("depot_" <> &1)) do
      nil -> :ok
      table -> {:error, "the Depot holds data already (depot_#{table})"}
    end
  end

  defp users(old_users) do
    found = Map.new(old_users, &{&1["id"], user(&1["email"])})
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
    for table <- @tables do
      data[table]
      |> Enum.map(&row(table, &1, users))
      |> Enum.chunk_every(@chunk)
      |> Enum.each(&insert(table, &1))
    end
  end

  defp row(table, row, users) when table in @per_user,
    do: row |> atoms() |> Map.put(:user_id, users[row["user_id"]])

  defp row(_table, row, _users), do: atoms(row)

  defp atoms(row), do: Map.new(row, fn {column, value} -> {String.to_atom(column), value} end)

  defp insert("exchange_rates", rows) do
    Repo.insert_all("depot_exchange_rates", rows,
      on_conflict: {:replace, [:rate]},
      conflict_target: [:currency, :date]
    )
  end

  defp insert(table, rows), do: Repo.insert_all("depot_" <> table, rows)

  # A user who set up their Paperless in Abakus before the import gets the old app's settings.
  defp write_settings(old_users, users) do
    rows =
      for user <- old_users, Enum.any?(@settings, &user[&1]) do
        user
        |> Map.take(@settings ++ ~w(inserted_at updated_at))
        |> atoms()
        |> Map.put(:user_id, users[user["id"]])
      end

    Repo.insert_all("depot_settings", rows,
      on_conflict: {:replace, Enum.map(@settings, &String.to_atom/1)},
      conflict_target: [:user_id]
    )
  end

  defp copy_receipt_files(receipts, folder) do
    hashes = receipts |> Enum.map(& &1["sha256"]) |> Enum.uniq()
    Enum.each(hashes, &copy_receipt_file(folder, &1))
    length(hashes)
  end

  defp copy_receipt_file(folder, sha256) do
    source = receipt_source(folder, sha256)

    case Portfolios.store_receipt_file(File.read!(source)) do
      {:ok, ^sha256} -> :ok
      _other -> Repo.rollback("receipt file damaged: #{source}")
    end
  end
end

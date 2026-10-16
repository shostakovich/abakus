defmodule Abakus.Depot.PortfoliosFixtures do
  @moduledoc "Portfolios, accounts and transactions for tests."

  alias Abakus.Depot.Portfolios
  alias Abakus.Depot.Portfolios.{Account, Portfolio, Transaction}
  alias Abakus.Repo
  alias Abakus.Users.Scope

  @old_app Path.expand("../fixtures/depot", __DIR__)

  def portfolio_fixture(%Scope{user: user}, attrs \\ %{}),
    do: Repo.insert!(struct!(%Portfolio{user_id: user.id, name: "Langfristig"}, attrs))

  def account_fixture(%Scope{user: user}, attrs \\ %{}),
    do: Repo.insert!(struct!(%Account{user_id: user.id, name: "Konto", currency: "EUR"}, attrs))

  @doc "A transaction on `date`, at noon; `attrs` needs at least `type`."
  def transaction_fixture(%Scope{user: user}, date, attrs) do
    Repo.insert!(
      struct!(
        %Transaction{
          user_id: user.id,
          date_time: NaiveDateTime.new!(date, ~T[12:00:00]),
          amount: 0,
          currency: "EUR",
          source: :manual
        },
        attrs
      )
    )
  end

  @doc "Shares as stored, × 10⁸."
  def shares(count), do: round(count * 100_000_000)

  @doc "An amount as stored, in cents of its currency."
  def money(value), do: round(value * 100)

  @doc """
  The former portfolio app's database file in `dir`, with its receipts folder next to it; returns its path. The
  receipt files an import brings in go when the test ends.
  """
  def old_app_file!(dir) do
    File.mkdir_p!(dir)
    path = Path.join(dir, "old.sqlite3")
    {:ok, db} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(db, File.read!(Path.join(@old_app, "old_app.sql")))
    :ok = Exqlite.Sqlite3.close(db)

    receipts = Path.join(@old_app, "receipts")
    File.cp_r!(receipts, Path.join(dir, "receipts"))

    ExUnit.Callbacks.on_exit(fn ->
      for file <- File.ls!(receipts), do: File.rm(Portfolios.receipt_file(Path.rootname(file)))
    end)

    path
  end
end

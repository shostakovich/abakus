defmodule Abakus.TestMigrations do
  @moduledoc "Runs the app's migrations on another database than the sandboxed one."

  alias Abakus.Repo

  @doc "Starts the repo on a new database in `dir` for the test and makes it the test's dynamic repo."
  def start_repo!(dir) do
    path = Path.join(dir, "abakus.sqlite3")

    repo =
      ExUnit.Callbacks.start_supervised!(
        {Repo, name: nil, database: path, pool: DBConnection.ConnectionPool, pool_size: 1},
        id: {Repo, path}
      )

    Repo.put_dynamic_repo(repo)
    ExUnit.Callbacks.on_exit(fn -> Repo.put_dynamic_repo(Repo) end)
    repo
  end

  def run!(repo, opts \\ [all: true]),
    do: Ecto.Migrator.run(Repo, migrations(), :up, opts ++ [dynamic_repo: repo, log: false])

  defp migrations do
    :global.trans({__MODULE__, self()}, fn ->
      with nil <- :persistent_term.get(__MODULE__, nil) do
        migrations = Enum.map(files(), &compile/1)
        :persistent_term.put(__MODULE__, migrations)
        migrations
      end
    end)
  end

  defp files,
    do: Repo |> Ecto.Migrator.migrations_path() |> Path.join("*.exs") |> Path.wildcard()

  defp compile(file) do
    {version, "_" <> _} = Integer.parse(Path.basename(file))
    [{module, _binary}] = Code.compile_file(file)
    {version, module}
  end
end

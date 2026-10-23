defmodule AbakusWeb.HealthControllerTest do
  use AbakusWeb.ConnCase

  import ExUnit.CaptureLog
  import Abakus.DomainFixtures

  alias Abakus.{BankSync, BankSyncFixtures, Repo}
  alias Abakus.BankSync.FakeClient

  test "GET /up reports the database as up", %{conn: conn} do
    assert conn |> get(~p"/up") |> json_response(200) == %{"status" => "up"}
  end

  test "GET /up answers 503 when the database cannot be reached and logs why", %{conn: conn} do
    # A second repo below a regular file cannot connect; it lives in capture_log as its errors log asynchronously.
    log =
      capture_log(fn ->
        repo =
          start_supervised!({
            Abakus.Repo,
            name: nil,
            database: "/dev/null/abakus.sqlite3",
            pool: DBConnection.ConnectionPool,
            pool_size: 1,
            queue_target: 10,
            queue_interval: 10
          })

        Abakus.Repo.put_dynamic_repo(repo)

        # The error stays in the log; the public endpoint does not reveal it.
        assert conn |> get(~p"/up") |> json_response(503) == %{"status" => "down"}

        Abakus.Repo.put_dynamic_repo(Abakus.Repo)
        stop_supervised!(Abakus.Repo)
      end)

    assert log =~ ~r/\[error\] Health check failed: .*connection not available/
  end

  test "GET /up answers 503 while a bank connection has failed for more than a day", %{conn: conn} do
    FakeClient.serve()
    connection = BankSyncFixtures.connection_fixture()
    [current, _savings] = connection.linked_accounts

    {:ok, connection} =
      BankSync.assign_accounts(budget_scope(), connection, %{
        current.id => %{account_id: account_fixture().id, start_date: ~D[2026-10-01]}
      })

    a_day_ago = DateTime.add(DateTime.utc_now(), -25, :hour)

    connection
    |> Ecto.Changeset.change(last_error: "Musterbank: abgelehnt", last_sync_at: a_day_ago)
    |> Repo.update!()

    log =
      capture_log(fn ->
        assert conn |> get(~p"/up") |> json_response(503) == %{"status" => "down"}
      end)

    assert log =~ "Health check failed: a bank connection has had no successful fetch"
  end

  # Changes the global log level, so the module stays synchronous.
  test "health checks stay out of the request log", %{conn: conn} do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    log = capture_log(fn -> get(conn, ~p"/up") end)
    refute log =~ "GET /up"

    log = capture_log(fn -> get(build_conn(), ~p"/") end)
    assert log =~ "GET /"
  end
end

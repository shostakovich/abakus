defmodule AbakusWeb.HealthControllerTest do
  use AbakusWeb.ConnCase

  import ExUnit.CaptureLog

  test "GET /up reports the database as up", %{conn: conn} do
    assert conn |> get(~p"/up") |> json_response(200) == %{"status" => "up"}
  end

  test "GET /up answers 503 when the database cannot be reached and logs why", %{conn: conn} do
    # A second repo for this test process only, below a regular file, so it cannot connect.
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

    log =
      capture_log(fn ->
        # The error stays in the log; the public endpoint does not reveal it.
        assert conn |> get(~p"/up") |> json_response(503) == %{"status" => "down"}
      end)

    assert log =~ ~r/\[error\] Health check failed: .*connection not available/
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

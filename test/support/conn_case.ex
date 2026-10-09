defmodule AbakusWeb.ConnCase do
  @moduledoc """
  Test case for tests that build a connection; database changes are rolled back via the sandbox.
  """

  use ExUnit.CaseTemplate

  alias Abakus.Users.Scope

  using do
    quote do
      @endpoint AbakusWeb.Endpoint

      use AbakusWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import AbakusWeb.ConnCase
    end
  end

  setup tags do
    Abakus.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that creates a user and signs them in; `@tag signed_in_minutes_ago: n` backdates
  the sign-in, computed when the test runs.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = Abakus.UsersFixtures.user_fixture()

    opts =
      case context[:signed_in_minutes_ago] do
        nil -> []
        minutes -> [token_authenticated_at: DateTime.add(DateTime.utc_now(), -minutes, :minute)]
      end

    %{conn: log_in_user(conn, user, opts), user: user, scope: Scope.for_user(user)}
  end

  @doc "Puts a fresh session token for `user` into the conn's session."
  def log_in_user(conn, user, opts \\ []) do
    token = Abakus.Users.generate_user_session_token(user)

    if authenticated_at = opts[:token_authenticated_at] do
      Abakus.UsersFixtures.override_token_authenticated_at(token, authenticated_at)
    end

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc "Waits until the tasks started under `Abakus.TaskSupervisor` (e.g. sign-in mails) are done."
  def await_background_tasks do
    for pid <- Task.Supervisor.children(Abakus.TaskSupervisor) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end

    :ok
  end
end

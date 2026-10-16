defmodule AbakusWeb.ConnCase do
  @moduledoc """
  Test case for tests that build a connection; database changes are rolled back via the sandbox.
  """

  use ExUnit.CaseTemplate

  alias Abakus.Kasse.Participants
  alias Abakus.Users.Scope

  using do
    quote do
      @endpoint AbakusWeb.Endpoint

      use AbakusWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import AbakusWeb.ConnCase
      import Setzkasten.Test.Confirm
    end
  end

  setup tags do
    Abakus.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  The selector of the sidebar's link to `path`. Setzkasten's shell renders the navigation more than
  once (sidebar, rail, its dialog, dock); this is the one in the sidebar.
  """
  def sidebar_link(path), do: ~s(aside nav[aria-label="Hauptnavigation"] a[href="#{path}"])

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

  @doc "Like `register_and_log_in_user/1`, but someone else registered first and owns the budget."
  def register_and_log_in_user_without_budget(context) do
    Abakus.UsersFixtures.user_fixture()
    register_and_log_in_user(context)
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

  @doc "Signs in the user of the Kasse's person with `participant_id`."
  def log_in_participant(conn, participant_id) do
    participant = participant_id |> Participants.get_participant!() |> Abakus.Repo.preload(:user)
    log_in_user(conn, participant.user)
  end

  @doc "Fixes `Abakus.LocalTime.today/0` for the rest of the test; for synchronous tests only."
  def fix_today(%Date{} = date) do
    Application.put_env(:abakus, :today, date)
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:abakus, :today) end)
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

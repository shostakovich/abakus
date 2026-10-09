defmodule Abakus.DataCase do
  @moduledoc """
  Test case for tests that use the database; changes are rolled back via the sandbox. SQLite allows one
  writer, so these tests run synchronously.
  """

  use ExUnit.CaseTemplate

  alias Abakus.RateLimit
  alias Abakus.WebAuthn.Challenges
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Abakus.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Abakus.DataCase
    end
  end

  setup tags do
    Abakus.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Starts a sandbox owner for the test, shared unless the test is async, and clears the rate
  limits and passkey challenges, which live outside the database.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Abakus.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    RateLimit.reset()
    Challenges.reset()
  end

  @doc """
  Turns changeset errors into a map of messages.

      assert %{name: ["can't be blank"]} = errors_on(changeset)
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

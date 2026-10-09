defmodule AbakusWeb.ConnCase do
  @moduledoc """
  Test case for tests that build a connection; database changes are rolled back via the sandbox.
  """

  use ExUnit.CaseTemplate

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
end

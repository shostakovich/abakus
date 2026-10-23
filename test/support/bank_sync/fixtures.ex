defmodule Abakus.BankSyncFixtures do
  @moduledoc "Bank connections of the budget owner, connected through `Abakus.BankSync.FakeClient`."

  alias Abakus.BankSync

  import Abakus.DomainFixtures, only: [budget_scope: 0]

  @doc "Connects Musterbank with `FakeClient.session/0`; the fake must be served."
  def connection_fixture do
    {:ok, %{auth: auth}} =
      BankSync.authorize(
        budget_scope(),
        %{name: "Musterbank", country: "DE"},
        "http://localhost/callback"
      )

    {:ok, connection} = BankSync.connect(budget_scope(), auth, "code-1")
    connection
  end
end

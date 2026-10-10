defmodule AbakusWeb.Api.PlanController do
  @moduledoc "The one plan with its accounts; accounts come along whether `include_accounts` asks for them or not."

  use AbakusWeb, :controller

  alias Abakus.Ledger
  alias AbakusWeb.Api.YnabJSON

  def index(conn, _params) do
    plan = YnabJSON.plan(Ledger.list_accounts(), Ledger.balances())
    json(conn, %{data: %{plans: [plan], default_plan: nil}})
  end
end

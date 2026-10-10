defmodule AbakusWeb.Api.AccountController do
  @moduledoc false

  use AbakusWeb, :controller

  alias Abakus.Ledger
  alias AbakusWeb.Api
  alias AbakusWeb.Api.YnabJSON

  action_fallback AbakusWeb.Api.FallbackController

  def show(conn, %{"account_id" => id}) do
    with {:ok, account} <- Api.find_account(id) do
      json(conn, %{data: %{account: YnabJSON.account(account, Ledger.balances())}})
    end
  end
end

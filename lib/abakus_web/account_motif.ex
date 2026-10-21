defmodule AbakusWeb.AccountMotif do
  @moduledoc """
  The plush of an account whose name has no leading emoji: the Kasse's for the shared-expenses account, else its kind's.
  """

  alias Abakus.Ledger.Account

  @kinds %{
    checking: "landmark",
    savings: "piggy-bank",
    cash: "banknote",
    tracking: "trending-up"
  }

  @doc ~s(The plush of an account: a checking account's is `"landmark"`.)
  def for_account(%Account{shared_expenses: true}), do: "receipt"
  def for_account(%Account{kind: kind}), do: Map.fetch!(@kinds, kind)
end

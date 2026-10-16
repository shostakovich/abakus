defmodule AbakusWeb.AccountMotif do
  @moduledoc """
  The plush of an account whose name has no leading emoji: the area that feeds it, else its kind.
  """

  alias Abakus.Ledger.Account

  @kinds %{
    checking: "landmark",
    savings: "piggy-bank",
    cash: "banknote",
    tracking: "trending-up"
  }

  @doc ~s(The plush of an account: a checking account's is `"landmark"`.)
  def for_account(%Account{fed_by: :shared_expenses}), do: "receipt"
  def for_account(%Account{fed_by: :portfolio}), do: "briefcase"
  def for_account(%Account{kind: kind}), do: Map.fetch!(@kinds, kind)
end

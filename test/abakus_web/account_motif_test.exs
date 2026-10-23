defmodule AbakusWeb.AccountMotifTest do
  use ExUnit.Case, async: true

  alias Abakus.Ledger.Account
  alias AbakusWeb.AccountMotif

  for {account, plush} <- [
        {%Account{kind: :checking}, "landmark"},
        {%Account{kind: :savings}, "piggy-bank"},
        {%Account{kind: :cash}, "banknote"},
        {%Account{kind: :tracking}, "trending-up"},
        {%Account{kind: :checking, shared_expenses: true}, "receipt"}
      ] do
    test "#{inspect(Map.take(account, [:kind, :shared_expenses]))} shows #{plush}" do
      assert AccountMotif.for_account(unquote(Macro.escape(account))) == unquote(plush)
      assert unquote(plush) in AbakusWeb.Plush.names()
    end
  end
end

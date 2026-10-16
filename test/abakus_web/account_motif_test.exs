defmodule AbakusWeb.AccountMotifTest do
  use ExUnit.Case, async: true

  alias Abakus.Ledger.Account
  alias AbakusWeb.AccountMotif

  for {account, plush} <- [
        {%Account{kind: :checking}, "landmark"},
        {%Account{kind: :savings}, "piggy-bank"},
        {%Account{kind: :cash}, "banknote"},
        {%Account{kind: :tracking}, "trending-up"},
        {%Account{kind: :checking, fed_by: :shared_expenses}, "receipt"},
        {%Account{kind: :tracking, fed_by: :portfolio}, "briefcase"}
      ] do
    test "#{inspect(Map.take(account, [:kind, :fed_by]))} shows #{plush}" do
      assert AccountMotif.for_account(unquote(Macro.escape(account))) == unquote(plush)
      assert unquote(plush) in AbakusWeb.Plush.names()
    end
  end
end

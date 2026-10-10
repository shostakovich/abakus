defmodule AbakusWeb.Api.TransactionParamsTest do
  use ExUnit.Case, async: true

  alias AbakusWeb.Api.TransactionParams

  @expense %{
    "account_id" => "3",
    "date" => "2026-10-08",
    "amount" => -42_500,
    "payee_name" => "Edeka",
    "memo" => "zipfelkasse #7",
    "category_id" => nil,
    "cleared" => "cleared",
    "approved" => true
  }

  describe "for_create/1" do
    test "keeps the writable fields and turns milliunits into cents" do
      assert TransactionParams.for_create(%{"transactions" => [@expense, %{"amount" => 10}]}) ==
               {:ok, [%{@expense | "amount" => -4_250}, %{"amount" => 1}]}
    end

    test "needs a list with at least one transaction" do
      for params <- [
            %{},
            %{"transactions" => []},
            %{"transactions" => %{}},
            %{"_json" => [@expense]}
          ] do
        assert {:error, "transactions muss" <> _} = TransactionParams.for_create(params)
      end
    end

    test "refuses amounts that are not whole cents or no whole number" do
      assert {:error, "Buchung 2: amount -42505 ist kein ganzer Cent-Betrag" <> _} =
               TransactionParams.for_create(%{
                 "transactions" => [@expense, %{@expense | "amount" => -42_505}]
               })

      for amount <- [12.5, -42_500.0, "-42500", nil] do
        assert {:error, "Buchung 1: amount muss eine ganze Zahl in Milliunits sein"} =
                 TransactionParams.for_create(%{"transactions" => [%{"amount" => amount}]})
      end
    end

    test "refuses fields the API does not write, and transactions that are no objects" do
      params = %{
        "transactions" => [Map.merge(@expense, %{"flag_color" => "red", "import_id" => "x"})]
      }

      assert TransactionParams.for_create(params) ==
               {:error, "Buchung 1: flag_color, import_id schreibt die API nicht"}

      assert {:error, "Buchung 1: id schreibt" <> _} =
               TransactionParams.for_create(%{"transactions" => [Map.put(@expense, "id", "1")]})

      assert TransactionParams.for_create(%{"transactions" => ["x"]}) ==
               {:error, "Buchung 1: ist kein Objekt"}
    end

    test "account and category ids must be ids a row can have" do
      for field <- ["account_id", "category_id"],
          id <- ["9223372036854775808", 9_223_372_036_854_775_808, "0", "x", [1]] do
        assert TransactionParams.for_create(%{"transactions" => [%{field => id}]}) ==
                 {:error, "Buchung 1: #{field} ist keine gültige Id"}
      end

      assert {:ok, _} =
               TransactionParams.for_create(%{
                 "transactions" => [%{"account_id" => "9223372036854775807", "category_id" => 3}]
               })
    end

    test "a payee name is a text" do
      assert {:error, "Buchung 1: payee_name muss ein Text sein"} =
               TransactionParams.for_create(%{"transactions" => [%{"payee_name" => 1}]})
    end
  end

  describe "for_update/1" do
    test "reads the id apart from the attrs" do
      assert TransactionParams.for_update(%{
               "transactions" => [%{"id" => "7", "amount" => -1_000, "memo" => "neu"}]
             }) == {:ok, [{"7", %{"amount" => -100, "memo" => "neu"}}]}
    end

    test "needs an id and checks the fields as on create" do
      assert TransactionParams.for_update(%{"transactions" => [%{"memo" => "neu"}]}) ==
               {:error, "Buchung 1: id fehlt"}

      assert {:error, "Buchung 1: amount" <> _} =
               TransactionParams.for_update(%{"transactions" => [%{"id" => "7", "amount" => 1}]})

      assert {:error, "Buchung 1: deleted schreibt" <> _} =
               TransactionParams.for_update(%{
                 "transactions" => [%{"id" => "7", "deleted" => true}]
               })
    end
  end
end

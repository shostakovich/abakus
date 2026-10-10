defmodule AbakusWeb.Api.YnabApiTest do
  @moduledoc """
  The cases of the shared-expenses app's fake YNAB server (Zipfelkasse's `internal/ynab/fake_test.go`, formerly
  `spec/support/fake_ynab.cr`), answered by Abakus.
  """

  use AbakusWeb.ConnCase

  import Abakus.DomainFixtures
  import Abakus.UsersFixtures

  alias Abakus.{ApiTokens, Categories, Ledger, Repo}
  alias Abakus.Ledger.Transaction

  @plan "/api/v1/plans/abakus"

  setup %{conn: conn} do
    {:ok, token, api_token} = ApiTokens.create_api_token(%{name: "Zipfelkasse"})
    shared = account_fixture(name: "Geteilt", kind: :cash, fed_by: :shared_expenses)

    %{
      conn: authorized(conn, token),
      token: token,
      api_token: api_token,
      shared: shared,
      category: category_fixture(name: "Lebensmittel")
    }
  end

  defp authorized(conn, token) do
    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  defp error(conn, status) do
    assert %{"error" => %{"id" => _, "name" => _, "detail" => detail}} =
             json_response(conn, status)

    detail
  end

  defp save(attrs), do: %{"transactions" => [attrs]}

  defp expense(c, attrs \\ %{}) do
    Map.merge(
      %{
        "account_id" => to_string(c.shared.id),
        "date" => "2026-10-08",
        "amount" => -42_500,
        "payee_name" => "Edeka",
        "memo" => "Gesamt 85,00 € · bezahlt von Anna · zipfelkasse #7",
        "category_id" => to_string(c.category.id),
        "cleared" => "cleared",
        "approved" => true
      },
      attrs
    )
  end

  defp create!(c, attrs \\ %{}) do
    conn = post(c.conn, "#{@plan}/transactions", save(expense(c, attrs)))
    assert %{"data" => %{"transactions" => [transaction]}} = json_response(conn, 201)
    transaction
  end

  defp stored(%{"id" => id}), do: Repo.get!(Transaction, String.to_integer(id))

  describe "token" do
    test "a request without a valid token is refused in YNAB's format", c do
      for conn <- [
            build_conn(),
            put_req_header(build_conn(), "authorization", "Bearer abk_wrong"),
            put_req_header(build_conn(), "authorization", c.token)
          ] do
        conn = get(conn, "/api/v1/plans?include_accounts=true")

        assert %{"error" => %{"id" => "401", "name" => "not_authorized"}} =
                 json_response(conn, 401)
      end
    end

    test "a revoked token is refused at once", c do
      assert json_response(get(c.conn, "/api/v1/plans"), 200)

      {:ok, _} = ApiTokens.revoke_api_token(c.api_token.id)

      assert error(get(c.conn, "/api/v1/plans"), 401)
    end

    test "records when the token was last used", c do
      get(c.conn, "/api/v1/plans")

      assert [%{last_used_at: %DateTime{}}] = ApiTokens.list_api_tokens()
    end

    test "a signed-in browser session is no token", c do
      conn = build_conn() |> log_in_user(user_fixture()) |> get("/api/v1/plans")

      assert %{"error" => %{"id" => "401", "name" => "not_authorized"}} =
               json_response(conn, 401)

      created = create!(c)

      conn =
        build_conn()
        |> log_in_user(user_fixture())
        |> delete("#{@plan}/transactions/#{created["id"]}")

      assert error(conn, 401)
      refute stored(created).deleted_at
    end

    test "unknown paths answer 404 to a token, 401 without one", c do
      assert %{"error" => %{"id" => "404.2", "name" => "resource_not_found"}} =
               json_response(get(c.conn, "/api/v1/budgets"), 404)

      assert error(get(build_conn(), "/api/v1/budgets"), 401)
    end
  end

  test "an unknown plan id is not found", c do
    for conn <- [
          get(c.conn, "/api/v1/plans/plan-1/categories"),
          get(c.conn, "/api/v1/plans/plan-1/accounts/#{c.shared.id}"),
          get(c.conn, "/api/v1/plans/plan-1/accounts/#{c.shared.id}/transactions"),
          post(c.conn, "/api/v1/plans/plan-1/transactions", save(expense(c))),
          patch(c.conn, "/api/v1/plans/plan-1/transactions", %{"transactions" => []}),
          delete(c.conn, "/api/v1/plans/plan-1/transactions/1")
        ] do
      assert %{"error" => %{"id" => "404.2"}} = json_response(conn, 404)
    end

    assert Repo.aggregate(Transaction, :count) == 0
  end

  test "GET /plans lists the one plan with its accounts and balances", c do
    giro = account_fixture(name: "Girokonto", kind: :checking)
    depot = account_fixture(name: "Depot", kind: :tracking)
    {:ok, old} = Ledger.update_account(account_fixture(name: "Altes Konto"), %{closed: true})
    transaction_fixture(account_id: giro.id, amount: 10_000, cleared: :cleared)
    transaction_fixture(account_id: giro.id, amount: -2_550)

    conn = get(c.conn, "/api/v1/plans?include_accounts=true")

    assert %{"data" => %{"plans" => [plan]}} = json_response(conn, 200)
    assert %{"id" => "abakus", "currency_format" => %{"iso_code" => "EUR"}} = plan
    accounts = Map.new(plan["accounts"], &{&1["name"], &1})

    assert accounts["Geteilt"] == %{
             "id" => to_string(c.shared.id),
             "name" => "Geteilt",
             "type" => "cash",
             "on_budget" => true,
             "closed" => false,
             "note" => nil,
             "balance" => 0,
             "cleared_balance" => 0,
             "uncleared_balance" => 0,
             "deleted" => false
           }

    assert %{
             "id" => giro_id,
             "type" => "checking",
             "balance" => 74_500,
             "cleared_balance" => 100_000,
             "uncleared_balance" => -25_500
           } = accounts["Girokonto"]

    assert giro_id == to_string(giro.id)
    assert %{"type" => "otherAsset", "on_budget" => false} = accounts["Depot"]
    assert accounts["Depot"]["id"] == to_string(depot.id)
    assert %{"closed" => true} = accounts["Altes Konto"]
    assert accounts["Altes Konto"]["id"] == to_string(old.id)
  end

  test "GET categories lists the groups with Ready to Assign, none hidden, not internal to the client",
       c do
    hidden = category_fixture(category_group_id: c.category.category_group_id, hidden: true)
    rta = Categories.ready_to_assign!()

    conn = get(c.conn, "#{@plan}/categories")

    assert %{"data" => %{"category_groups" => [internal, group]}} = json_response(conn, 200)

    assert %{
             "name" => "Internal Master Category",
             "internal" => true,
             "hidden" => false,
             "deleted" => false,
             "categories" => [%{"name" => "Inflow: Ready to Assign"} = ready_to_assign]
           } = internal

    assert ready_to_assign["id"] == to_string(rta.id)
    assert group["id"] == to_string(c.category.category_group_id)

    assert [
             %{"id" => category_id, "name" => "Lebensmittel", "hidden" => false},
             %{"id" => hidden_id, "hidden" => false, "deleted" => false}
           ] = group["categories"]

    assert {category_id, hidden_id} == {to_string(c.category.id), to_string(hidden.id)}
  end

  describe "GET one account" do
    test "answers the account", c do
      conn = get(c.conn, "#{@plan}/accounts/#{c.shared.id}")

      assert %{"data" => %{"account" => %{"name" => "Geteilt", "type" => "cash"} = account}} =
               json_response(conn, 200)

      assert account["id"] == to_string(c.shared.id)
    end

    test "an unknown account is not found", c do
      assert error(get(c.conn, "#{@plan}/accounts/999999"), 404)
      assert error(get(c.conn, "#{@plan}/accounts/acc-geteilt"), 404)
    end
  end

  describe "GET an account's transactions" do
    test "lists the register from since_date on, without deleted ones", c do
      giro = account_fixture()
      transaction_fixture(account_id: c.shared.id, date: ~D[2026-09-30])
      on_the_day = transaction_fixture(account_id: c.shared.id, date: ~D[2026-10-01])
      later = transaction_fixture(account_id: c.shared.id, date: ~D[2026-10-05])
      transaction_fixture(account_id: giro.id, date: ~D[2026-10-05])
      {:ok, _} = Ledger.delete_transaction(transaction_fixture(account_id: c.shared.id))

      conn = get(c.conn, "#{@plan}/accounts/#{c.shared.id}/transactions?since_date=2026-10-01")

      assert %{"data" => %{"transactions" => transactions}} = json_response(conn, 200)
      assert Enum.map(transactions, & &1["id"]) == [to_string(on_the_day.id), to_string(later.id)]

      conn = get(c.conn, "#{@plan}/accounts/#{c.shared.id}/transactions")
      assert length(json_response(conn, 200)["data"]["transactions"]) == 3
    end

    test "a bad since_date or an unknown account is refused", c do
      assert error(get(c.conn, "#{@plan}/accounts/#{c.shared.id}/transactions?since_date=x"), 400)

      assert error(
               get(c.conn, "#{@plan}/accounts/#{c.shared.id}/transactions?since_date[]=x"),
               400
             )

      assert error(get(c.conn, "#{@plan}/accounts/999999/transactions"), 404)
    end
  end

  describe "POST transactions" do
    test "creates them and answers them in YNAB's format", c do
      second = expense(c, %{"amount" => 1_230, "memo" => "zipfelkasse #8", "approved" => false})

      conn =
        post(c.conn, "#{@plan}/transactions", %{"transactions" => [expense(c), second]})

      assert %{"data" => %{"transaction_ids" => ids, "transactions" => [first, other]}} =
               json_response(conn, 201)

      assert ids == [first["id"], other["id"]]

      assert first == %{
               "id" => first["id"],
               "account_id" => to_string(c.shared.id),
               "date" => "2026-10-08",
               "amount" => -42_500,
               "payee_name" => "Edeka",
               "memo" => "Gesamt 85,00 € · bezahlt von Anna · zipfelkasse #7",
               "category_id" => to_string(c.category.id),
               "cleared" => "cleared",
               "approved" => true,
               "deleted" => false
             }

      assert %{amount: -4_250, source: :api, approved: true} = stored(first)
      assert %{amount: 123, approved: false} = stored(other)
    end

    test "without category, cleared and approval a transaction is uncategorised, uncleared and unapproved",
         c do
      transaction = create!(c, %{"category_id" => nil}) |> stored()
      assert %{category_id: nil} = transaction

      attrs = Map.drop(expense(c), ["category_id", "cleared", "approved"])
      conn = post(c.conn, "#{@plan}/transactions", save(attrs))

      assert %{"data" => %{"transactions" => [created]}} = json_response(conn, 201)
      assert %{"category_id" => nil, "cleared" => "uncleared", "approved" => false} = created
    end

    test "a request without transactions is refused", c do
      for body <- [
            %{},
            %{"transactions" => []},
            %{"transactions" => "x"},
            %{"transactions" => ["x"]}
          ] do
        assert error(post(c.conn, "#{@plan}/transactions", body), 400)
      end
    end

    test "amounts that are not whole cents refuse the whole request", c do
      for amount <- [-42_505, 12.5, "-42500", nil] do
        body = %{"transactions" => [expense(c), expense(c, %{"amount" => amount})]}
        detail = error(post(c.conn, "#{@plan}/transactions", body), 400)
        assert detail =~ "amount"
      end

      assert Repo.aggregate(Transaction, :count) == 0
    end

    test "fields the API does not write are refused", c do
      for {field, value} <- [
            {"import_id", "YNAB:-42500:2026-10-08:1"},
            {"flag_color", "red"},
            {"subtransactions", []},
            {"id", "1"}
          ] do
        detail =
          error(post(c.conn, "#{@plan}/transactions", save(expense(c, %{field => value}))), 400)

        assert detail =~ field
      end

      assert Repo.aggregate(Transaction, :count) == 0
    end

    test "what the Ledger refuses is refused as a whole", c do
      depot = account_fixture(kind: :tracking)

      for attrs <- [
            %{"account_id" => "999999"},
            %{"account_id" => to_string(depot.id)},
            %{"category_id" => "999999"},
            %{"date" => "08.10.2026"},
            %{"cleared" => "pending"}
          ] do
        body = %{"transactions" => [expense(c), expense(c, attrs)]}
        assert error(post(c.conn, "#{@plan}/transactions", body), 400)
      end

      assert Repo.aggregate(Transaction, :count) == 0
    end
  end

  describe "PATCH transactions" do
    test "changes the transactions by id and answers them", c do
      created = create!(c)
      other = create!(c, %{"memo" => "zipfelkasse #8"})

      changes = [
        %{
          "id" => created["id"],
          "date" => "2026-10-09",
          "amount" => -50_000,
          "payee_name" => "Rewe",
          "memo" => "Gesamt 100,00 € · zipfelkasse #7",
          "category_id" => nil
        },
        %{"id" => other["id"], "cleared" => "uncleared", "approved" => false}
      ]

      conn = patch(c.conn, "#{@plan}/transactions", %{"transactions" => changes})

      assert %{"data" => %{"transactions" => [changed, changed_other]}} = json_response(conn, 200)

      assert %{
               "date" => "2026-10-09",
               "amount" => -50_000,
               "payee_name" => "Rewe",
               "category_id" => nil,
               "cleared" => "cleared"
             } = changed

      assert %{"cleared" => "uncleared", "approved" => false, "memo" => "zipfelkasse #8"} =
               changed_other

      assert %{amount: -5_000, category_id: nil} = stored(created)
    end

    test "leaves the category alone when the request does not name one", c do
      created = create!(c)

      conn =
        patch(c.conn, "#{@plan}/transactions", %{
          "transactions" => [%{"id" => created["id"], "memo" => "neu"}]
        })

      assert %{"data" => %{"transactions" => [%{"category_id" => category_id}]}} =
               json_response(conn, 200)

      assert category_id == to_string(c.category.id)
    end

    test "an unknown id changes nothing and is not found", c do
      created = create!(c)

      changes = [%{"id" => created["id"], "memo" => "neu"}, %{"id" => "999999", "memo" => "neu"}]
      assert error(patch(c.conn, "#{@plan}/transactions", %{"transactions" => changes}), 404)

      assert stored(created).memo =~ "zipfelkasse #7"
    end

    test "a deleted transaction is answered as deleted and stays as it is", c do
      created = create!(c)
      {:ok, _} = Ledger.delete_transaction(stored(created))

      conn =
        patch(c.conn, "#{@plan}/transactions", %{
          "transactions" => [%{"id" => created["id"], "amount" => -1_000}]
        })

      assert %{"data" => %{"transactions" => [%{"deleted" => true, "amount" => -42_500}]}} =
               json_response(conn, 200)
    end

    test "a reconciled transaction cannot be changed: 409 and nothing changes", c do
      created = create!(c)
      reconciled = create!(c, %{"memo" => "zipfelkasse #8", "cleared" => "reconciled"})

      changes = [
        %{"id" => created["id"], "memo" => "neu"},
        %{"id" => reconciled["id"], "amount" => -1_000}
      ]

      conn = patch(c.conn, "#{@plan}/transactions", %{"transactions" => changes})

      assert %{"error" => %{"id" => "409", "name" => "conflict"}} = json_response(conn, 409)
      assert stored(created).memo =~ "zipfelkasse #7"
      assert %{amount: -4_250, cleared: :reconciled} = stored(reconciled)
    end

    test "amounts that are not whole cents and changes without id are refused", c do
      created = create!(c)

      for change <- [%{"id" => created["id"], "amount" => -1_001}, %{"amount" => -1_000}] do
        assert error(patch(c.conn, "#{@plan}/transactions", %{"transactions" => [change]}), 400)
      end

      assert stored(created).amount == -4_250
    end
  end

  describe "DELETE a transaction" do
    test "deletes it and answers it as deleted", c do
      created = create!(c)

      conn = delete(c.conn, "#{@plan}/transactions/#{created["id"]}")

      assert %{"data" => %{"transaction" => %{"id" => id, "deleted" => true}}} =
               json_response(conn, 200)

      assert id == created["id"]
      assert stored(created).deleted_at

      conn = get(c.conn, "#{@plan}/accounts/#{c.shared.id}/transactions")
      assert json_response(conn, 200)["data"]["transactions"] == []
    end

    test "a deleted or unknown transaction is not found", c do
      created = create!(c)
      delete(c.conn, "#{@plan}/transactions/#{created["id"]}")

      assert error(delete(c.conn, "#{@plan}/transactions/#{created["id"]}"), 404)
      assert error(delete(c.conn, "#{@plan}/transactions/999999"), 404)
      assert error(delete(c.conn, "#{@plan}/transactions/t1"), 404)
    end

    test "a reconciled transaction is not deleted: 409", c do
      reconciled = create!(c, %{"cleared" => "reconciled"})

      assert %{"error" => %{"id" => "409"}} =
               json_response(delete(c.conn, "#{@plan}/transactions/#{reconciled["id"]}"), 409)

      refute stored(reconciled).deleted_at
    end
  end

  describe "a transfer whose counterpart is reconciled" do
    setup c do
      giro = account_fixture(name: "Girokonto", kind: :checking)

      {:ok, transfer} =
        Ledger.create_transaction(%{
          account_id: c.shared.id,
          date: ~D[2026-10-08],
          amount: -1_000,
          payee_id: giro.transfer_payee.id
        })

      counterpart = Repo.get!(Transaction, transfer.transfer_transaction_id)
      {:ok, _} = Ledger.update_transaction(counterpart, %{cleared: :reconciled})

      %{
        transfer: Repo.get!(Transaction, transfer.id),
        counterpart: Repo.get!(Transaction, counterpart.id)
      }
    end

    test "is not changed: 409 and nothing changes", c do
      change = %{"transactions" => [%{"id" => to_string(c.transfer.id), "amount" => -20_000}]}
      conn = patch(c.conn, "#{@plan}/transactions", change)

      assert %{"error" => %{"id" => "409", "name" => "conflict"}} = json_response(conn, 409)
      assert Repo.get!(Transaction, c.transfer.id) == c.transfer
      assert Repo.get!(Transaction, c.counterpart.id) == c.counterpart
    end

    test "is not deleted: 409 and nothing changes", c do
      conn = delete(c.conn, "#{@plan}/transactions/#{c.transfer.id}")

      assert %{"error" => %{"id" => "409", "name" => "conflict"}} = json_response(conn, 409)
      assert Repo.get!(Transaction, c.transfer.id) == c.transfer
      assert Repo.get!(Transaction, c.counterpart.id) == c.counterpart
    end
  end

  test "ids beyond 64 bits are not found or refused, never an error", c do
    created = create!(c)
    huge = "99999999999999999999"

    assert error(get(c.conn, "#{@plan}/accounts/#{huge}"), 404)
    assert error(get(c.conn, "#{@plan}/accounts/#{huge}/transactions"), 404)
    assert error(delete(c.conn, "#{@plan}/transactions/#{huge}"), 404)

    patch = %{"transactions" => [%{"id" => huge, "memo" => "neu"}]}
    assert error(patch(c.conn, "#{@plan}/transactions", patch), 404)

    for field <- ["account_id", "category_id"] do
      assert error(post(c.conn, "#{@plan}/transactions", save(expense(c, %{field => huge}))), 400) =~
               field

      patch = %{"transactions" => [%{"id" => created["id"], field => huge}]}
      assert error(patch(c.conn, "#{@plan}/transactions", patch), 400) =~ field
    end

    assert Repo.aggregate(Transaction, :count) == 1
    assert stored(created).memo =~ "zipfelkasse #7"
  end

  test "match proposals count nowhere, so the API does not know them", c do
    manual = transaction_fixture(account_id: c.shared.id, amount: -4_250)

    {:ok, proposal} =
      Ledger.create_transaction(%{
        account_id: c.shared.id,
        date: ~D[2026-10-09],
        amount: -4_250,
        source: :file,
        matched_transaction_id: manual.id
      })

    conn = get(c.conn, "#{@plan}/accounts/#{c.shared.id}/transactions")
    assert [%{"id" => id}] = json_response(conn, 200)["data"]["transactions"]
    assert id == to_string(manual.id)

    change = %{"transactions" => [%{"id" => to_string(proposal.id), "memo" => "neu"}]}
    assert error(patch(c.conn, "#{@plan}/transactions", change), 404)
    assert error(delete(c.conn, "#{@plan}/transactions/#{proposal.id}"), 404)
  end

  test "a body that is no JSON is refused in YNAB's format", c do
    {400, _headers, body} =
      assert_error_sent(400, fn ->
        c.conn
        |> put_req_header("content-type", "application/json")
        |> post("#{@plan}/transactions", "{")
      end)

    assert %{"error" => %{"id" => "400", "name" => "bad_request"}} = JSON.decode!(body)
  end

  test "a body that is no JSON gets JSON without an Accept header", c do
    {400, headers, body} =
      assert_error_sent(400, fn ->
        build_conn()
        |> put_req_header("authorization", "Bearer " <> c.token)
        |> put_req_header("content-type", "application/json")
        |> post("#{@plan}/transactions", "{")
      end)

    assert {"content-type", "application/json" <> _} = List.keyfind(headers, "content-type", 0)

    assert %{
             "error" => %{"id" => "400", "name" => "bad_request", "detail" => "Ungültige Anfrage"}
           } =
             JSON.decode!(body)
  end

  test "a path outside /api/v1 is not found in YNAB's format" do
    assert %{"error" => %{"id" => "404.2", "name" => "resource_not_found", "detail" => detail}} =
             json_response(get(build_conn(), "/api/foo"), 404)

    assert detail == "Nicht gefunden"
  end
end

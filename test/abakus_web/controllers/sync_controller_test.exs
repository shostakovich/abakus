defmodule AbakusWeb.SyncControllerTest do
  use AbakusWeb.ConnCase

  import Abakus.DevicesFixtures
  import Abakus.DomainFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Abakus.{Categories, Devices, Ids, Repo, Sync}
  alias Abakus.Devices.Device
  alias Abakus.Ledger.{Scheduled, ScheduledTransaction, Transaction}

  setup do
    fix_now(~U[2026-11-02 10:00:00Z])
    scope = budget_scope()
    Categories.ready_to_assign!(scope)
    tokens = sign_in_device(scope)
    %{scope: scope, tokens: tokens, giro: account_fixture(name: "Girokonto")}
  end

  defp api(token, version \\ "1") do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("abakus-protocol", version)
  end

  defp sync(c, cursor, messages \\ []),
    do: api(c.tokens.access_token) |> post(~p"/api/sync", %{cursor: cursor, messages: messages})

  defp message(table, row_id, column, value, clock) do
    %{
      "table" => table,
      "row_id" => row_id,
      "column" => column,
      "value" => value,
      "clock" => clock
    }
  end

  defp mac_clock(c, at), do: "#{at}-0000-#{c.tokens.device_id}"

  test "applies the device's messages and answers with the others' after its cursor", c do
    rewe = transaction_fixture(account_id: c.giro.id, memo: "Rewe")
    cursor = Sync.cursor(c.scope)
    {:ok, _rewe} = Abakus.Ledger.update_transaction(c.scope, rewe, %{amount: -100})

    conn =
      sync(c, cursor, [
        message(
          "transactions",
          rewe.id,
          "memo",
          "Vom Mac",
          mac_clock(c, "2026-11-02T10:01:00.000Z")
        )
      ])

    assert %{"messages" => [answer], "cursor" => new_cursor, "more" => false} =
             json_response(conn, 200)

    assert answer == %{
             "table" => "transactions",
             "row_id" => rewe.id,
             "column" => "amount",
             "value" => -100,
             "clock" => answer["clock"]
           }

    assert new_cursor == Sync.cursor(c.scope)
    assert Repo.reload(rewe).memo == "Vom Mac"
    assert %Device{last_synced_at: %DateTime{}} = Repo.get!(Device, c.tokens.device_id)
  end

  test "with nothing new it answers after waiting, with the same cursor", c do
    cursor = Sync.cursor(c.scope)

    assert json_response(sync(c, cursor), 200) == %{
             "messages" => [],
             "cursor" => cursor,
             "more" => false
           }
  end

  test "a waiting sync request returns an edit made in a LiveView within a second", c do
    Application.put_env(:abakus, :sync_wait, 5_000)
    on_exit(fn -> Application.put_env(:abakus, :sync_wait, 100) end)

    transaction = transaction_fixture(account_id: c.giro.id, memo: "Alt")
    cursor = Sync.cursor(c.scope)
    waiting = Task.async(fn -> sync(c, cursor) end)
    await_subscribed(waiting.pid, c.scope)

    {:ok, view, _html} =
      live(log_in_user(build_conn(), c.scope.user), ~p"/budget/accounts/#{c.giro}")

    view |> element("#tx-#{transaction.id} td.app-payee") |> render_click()
    view |> element("#tx-#{transaction.id} td.app-payee") |> render_click()
    view |> form("#tx-form", transaction: %{memo: "Neu"}) |> render_submit()

    conn = Task.await(waiting, 1_000)

    assert %{"messages" => [%{"row_id" => id, "column" => "memo", "value" => "Neu"}]} =
             json_response(conn, 200)

    assert id == transaction.id
  end

  test "a waiting sync request of a device signed out meanwhile is refused once it wakes", c do
    Application.put_env(:abakus, :sync_wait, 5_000)
    on_exit(fn -> Application.put_env(:abakus, :sync_wait, 100) end)

    cursor = Sync.cursor(c.scope)
    waiting = Task.async(fn -> sync(c, cursor) end)
    await_subscribed(waiting.pid, c.scope)

    :ok = Devices.sign_out(c.scope, c.tokens.device_id)
    transaction_fixture(account_id: c.giro.id)

    conn = Task.await(waiting, 1_000)
    assert json_response(conn, 401) == %{"error" => "invalid_token"}
    assert get_resp_header(conn, "www-authenticate") != []
  end

  defp await_subscribed(pid, scope, tries \\ 100) do
    subscribed? =
      pid in Enum.map(
        Registry.lookup(Abakus.PubSub, "sync:#{scope.user.id}:written"),
        &elem(&1, 0)
      )

    cond do
      subscribed? -> :ok
      tries == 0 -> flunk("the sync request does not wait")
      true -> Process.sleep(10) && await_subscribed(pid, scope, tries - 1)
    end
  end

  test "a device whose clock runs ahead is refused whole with a clock error", c do
    rewe = transaction_fixture(account_id: c.giro.id, memo: "Rewe")

    conn =
      sync(c, 0, [
        message("transactions", rewe.id, "memo", "Mac", mac_clock(c, "2026-11-02T10:00:00.000Z")),
        message("transactions", rewe.id, "amount", -1, mac_clock(c, "2026-11-02T10:10:00.000Z"))
      ])

    assert %{"error" => "clock_ahead", "server_time" => "2026-11-02T10:00:00Z"} =
             json_response(conn, 400)

    assert %Transaction{memo: "Rewe"} = Repo.reload(rewe)
  end

  test "refuses messages of another device's clock and a bad cursor", c do
    rewe = transaction_fixture(account_id: c.giro.id)

    conn =
      sync(c, 0, [
        message("transactions", rewe.id, "memo", "x", "2026-11-02T10:00:00.000Z-0000-ipad")
      ])

    assert %{"error" => "invalid_request"} = json_response(conn, 400)

    assert %{"error" => "invalid_request"} = json_response(sync(c, -1), 400)
  end

  test "without a valid access token the API is refused", c do
    conn = post(build_conn(), ~p"/api/sync", %{cursor: 0})
    assert json_response(conn, 401) == %{"error" => "invalid_token"}
    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="Abakus")]

    conn = api("nix") |> get(~p"/api/snapshot")
    assert json_response(conn, 401) == %{"error" => "invalid_token"}

    assert get_resp_header(conn, "www-authenticate") == [
             ~s(Bearer realm="Abakus", error="invalid_token")
           ]

    Repo.update_all(Abakus.Users.User, set: [budget_owner: false])
    assert json_response(sync(c, 0), 401)
  end

  test "a protocol version the server no longer speaks asks to update the app", c do
    for version <- ["0", "2", ""] do
      conn = api(c.tokens.access_token, version) |> get(~p"/api/snapshot")

      assert %{"error" => "unsupported_protocol", "supported" => [1], "message" => message} =
               json_response(conn, 400)

      assert message =~ "aktualisiere"
    end
  end

  test "the snapshot holds every synced row with its fields' clocks, and the cursor", c do
    rewe = transaction_fixture(account_id: c.giro.id, memo: "Rewe")

    assert %{"cursor" => cursor, "tables" => tables} =
             json_response(api(c.tokens.access_token) |> get(~p"/api/snapshot"), 200)

    assert cursor == Sync.cursor(c.scope)

    assert %{"fields" => %{"memo" => "Rewe"}, "clocks" => %{"memo" => clock}} =
             Enum.find(tables["transactions"], &(&1["id"] == rewe.id))

    assert clock =~ "-server"
    assert Enum.any?(tables["accounts"], &(&1["id"] == c.giro.id))
  end

  describe "scenario: a due scheduled transaction is entered once" do
    test "the Mac offline and the daily job both enter Miete, Girokonto has it once", c do
      rent = category_fixture(name: "Miete")
      landlord = payee_fixture(name: "Vermieter")

      scheduled =
        %ScheduledTransaction{user_id: c.scope.user.id}
        |> ScheduledTransaction.changeset(%{
          account_id: c.giro.id,
          next_date: ~D[2026-12-01],
          frequency: :monthly,
          payee_id: landlord.id,
          category_id: rent.id,
          memo: "Miete",
          amount: -95_000
        })
        |> Repo.insert!()

      entered = Ids.entered_transaction(scheduled.id, ~D[2026-12-01])
      offline = mac_clock(c, "2026-12-01T07:00:00.000Z")

      mac_entry =
        for {column, value} <- [
              account_id: c.giro.id,
              date: "2026-12-01",
              amount: -95_000,
              memo: "Miete",
              payee_id: landlord.id,
              category_id: rent.id,
              cleared: "uncleared",
              approved: false,
              source: "scheduled",
              scheduled_transaction_id: scheduled.id,
              scheduled_date: "2026-12-01"
            ] do
          message("transactions", entered, to_string(column), value, offline)
        end ++
          [message("scheduled_transactions", scheduled.id, "next_date", "2027-01-01", offline)]

      fix_now(~U[2026-12-01 08:00:00Z])
      assert {:ok, 1} = Scheduled.enter_due(c.scope, ~D[2026-12-01])

      fix_now(~U[2026-12-01 09:00:00Z])
      assert json_response(sync(c, 0, mac_entry), 200)

      assert [%Transaction{id: ^entered, amount: -95_000, date: ~D[2026-12-01]}] =
               Repo.all(
                 from t in Transaction,
                   where:
                     t.account_id == ^c.giro.id and t.memo == "Miete" and is_nil(t.deleted_at)
               )

      assert Repo.reload(scheduled).next_date == ~D[2027-01-01]
    end
  end
end

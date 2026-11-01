defmodule AbakusWeb.SyncLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ids, Sync, SyncDevice}
  alias Abakus.Sync.Clock

  setup :register_and_log_in_user
  setup do: fix_today(~D[2026-11-02])

  setup do
    Categories.ready_to_assign!(budget_scope())

    %{
      giro: account_fixture(name: "💶 Girokonto"),
      groceries: category_fixture(name: "🛒 Lebensmittel")
    }
  end

  defp mac_message(table, row_id, column, value),
    do: %{
      "table" => table,
      "row_id" => row_id,
      "column" => column,
      "value" => value,
      "clock" => Clock.to_string(Clock.tick(nil, System.os_time(:millisecond) + 60_000, "mac"))
    }

  test "an edit in the register writes one message per changed field", c do
    transaction =
      transaction_fixture(account_id: c.giro.id, category_id: c.groceries.id, memo: "Alt")

    cursor = Sync.cursor(budget_scope())
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    view |> element("#tx-#{transaction.id} td.app-payee") |> render_click()
    view |> element("#tx-#{transaction.id} td.app-payee") |> render_click()
    view |> form("#tx-form", transaction: %{memo: "Neu", amount: "20,00"}) |> render_submit()

    messages = SyncDevice.messages_after(budget_scope(), cursor, "mac")

    assert Enum.sort(Enum.map(messages, &{&1.table, &1.row_id, &1.column, &1.value})) == [
             {"transactions", transaction.id, "amount", "-2000"},
             {"transactions", transaction.id, "memo", ~s("Neu")}
           ]
  end

  test "the register shows what another device changed", c do
    transaction = transaction_fixture(account_id: c.giro.id, memo: "Alt")
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    {:ok, 1} =
      Sync.apply_messages(budget_scope(), "mac", [
        mac_message("transactions", transaction.id, "memo", "Vom Mac")
      ])

    assert render(view) =~ "Vom Mac"
  end

  test "the budget shows what another device assigned", c do
    {:ok, view, _html} = live(c.conn, ~p"/budget")
    assignment = Ids.assignment(c.groceries.id, ~D[2026-11-01])

    {:ok, 3} =
      Sync.apply_messages(budget_scope(), "mac", [
        mac_message("assignments", assignment, "category_id", c.groceries.id),
        mac_message("assignments", assignment, "month", "2026-11-01"),
        mac_message("assignments", assignment, "amount", 2_500)
      ])

    assert has_element?(view, "#assign-#{c.groceries.id}-2026-11[value='25,00']")
  end
end

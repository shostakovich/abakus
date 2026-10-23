defmodule Abakus.BankSync.JobTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.BankSyncFixtures

  alias Abakus.{BankSync, Ledger, Repo}
  alias Abakus.BankSync.{Connection, FakeClient, Job}

  setup :register_and_log_in_user

  setup do
    FakeClient.serve()
    fix_now(~U[2026-10-20 10:00:00.000000Z])
    connection = connection_fixture()
    [current, _savings] = connection.linked_accounts
    giro = account_fixture(name: "Girokonto")

    {:ok, connection} =
      BankSync.assign_accounts(budget_scope(), connection, %{
        current.id => %{account_id: giro.id, start_date: ~D[2026-10-01]}
      })

    %{connection: connection, giro: giro}
  end

  test "a scheduled fetch run twice imports nothing the second time and keeps the bank balance",
       %{conn: conn, connection: connection, giro: giro} do
    FakeClient.put_transactions("uid-giro", [
      FakeClient.transaction(
        entry_reference: "E-1",
        date: ~D[2026-10-12],
        amount: -4200,
        creditor: "Stadtwerke"
      ),
      FakeClient.transaction(
        transaction_id: "T-2",
        date: ~D[2026-10-15],
        amount: 125_000,
        debtor: "Arbeitgeber GmbH"
      )
    ])

    FakeClient.put_balances("uid-giro", [
      %{type: :closing_booked, amount: 120_800, date: ~D[2026-10-08]}
    ])

    assert Job.run() == :ok
    assert Job.run() == :ok

    assert [%{new: 0, trigger: :scheduled}, %{new: 2, trigger: :scheduled}] =
             BankSync.get_connection!(budget_scope(), connection.id).sync_runs

    assert ["Arbeitgeber GmbH", "Stadtwerke"] =
             budget_scope() |> Ledger.list_transactions(giro) |> Enum.map(& &1.payee.name)

    assert Enum.all?(FakeClient.fetches(), &(elem(&1, tuple_size(&1) - 1) == nil))

    {:ok, view, _html} = live(conn, ~p"/budget/accounts/#{giro}")
    view |> element("#reconcile-open") |> render_click()

    assert has_element?(view, "#reconcile-bank", "08.10.2026")
    assert has_element?(view, "#reconcile-bank", Abakus.Money.euros(120_800))
  end

  test "an expired consent stops fetching", %{conn: conn, connection: connection} do
    Repo.update_all(Connection, set: [valid_until: ~U[2026-10-19 10:00:00.000000Z]])

    assert Job.run() == :ok

    assert FakeClient.fetches() == []
    assert BankSync.get_connection!(budget_scope(), connection.id).sync_runs == []
    refute_received {:email, %{subject: "Abakus: Freigabe" <> _rest}}

    {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")

    card = "#bank-connection-#{connection.id}"
    assert has_element?(view, card, "Freigabe abgelaufen")
    assert has_element?(view, "#{card}-renew", "Freigabe erneuern")
    assert has_element?(view, "#{card}-fetch[disabled]")
  end

  test "reports a failed fetch for the log" do
    FakeClient.fail_fetches(:rate_limited)

    assert {:error, "Musterbank: Girokonto: Die Bank hat den Abruf abgelehnt" <> _rest} =
             Job.run()
  end

  test "does nothing without bank sync set up" do
    stop_supervised!(FakeClient)

    assert Job.run() == :ok
  end
end

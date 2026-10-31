defmodule Abakus.Ledger.ScheduledTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Ecto.Query

  alias Abakus.{Ids, Ledger, Repo}
  alias Abakus.Ledger.{Scheduled, ScheduledTransaction, Transaction}

  setup do
    giro = account_fixture(name: "Girokonto", kind: :checking)
    rent = category_fixture(name: "Miete")
    landlord = payee_fixture(name: "Vermieter")
    %{giro: giro, rent: rent, landlord: landlord}
  end

  defp scheduled_fixture(c, attrs) do
    %ScheduledTransaction{user_id: budget_scope().user.id}
    |> ScheduledTransaction.changeset(
      Enum.into(attrs, %{
        account_id: c.giro.id,
        next_date: ~D[2026-12-01],
        frequency: :monthly,
        payee_id: c.landlord.id,
        category_id: c.rent.id,
        memo: "Miete",
        amount: -95_000
      })
    )
    |> Repo.insert!()
  end

  defp entered(account) do
    Repo.all(
      from t in Transaction,
        where: t.account_id == ^account.id and is_nil(t.deleted_at),
        order_by: t.date,
        preload: :subtransactions
    )
  end

  test "enters each occurrence up to today, unapproved, and moves the next date on", c do
    scheduled = scheduled_fixture(c, next_date: ~D[2026-10-01], cleared: :cleared)

    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-01]) == {:ok, 3}

    assert [
             %Transaction{date: ~D[2026-10-01]} = october,
             %Transaction{date: ~D[2026-11-01]},
             %Transaction{date: ~D[2026-12-01]}
           ] = entered(c.giro)

    assert october.id == Ids.entered_transaction(scheduled.id, ~D[2026-10-01])
    assert october.scheduled_transaction_id == scheduled.id
    assert october.scheduled_date == ~D[2026-10-01]

    assert %{
             amount: -95_000,
             payee_id: payee_id,
             category_id: category_id,
             memo: "Miete",
             cleared: :cleared,
             approved: false,
             source: :scheduled
           } = october

    assert {payee_id, category_id} == {c.landlord.id, c.rent.id}
    assert Repo.reload!(scheduled).next_date == ~D[2027-01-01]
    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-01]) == {:ok, 0}
  end

  test "a due scheduled transaction another writer entered already is entered once", c do
    scheduled = scheduled_fixture(c, [])

    {:ok, _on_the_mac} =
      Ledger.create_transaction(
        budget_scope(),
        %{account_id: c.giro.id, date: ~D[2026-12-01], amount: -95_000, memo: "Miete"},
        entered_from: {scheduled.id, ~D[2026-12-01]}
      )

    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-01]) == {:ok, 0}
    assert [%Transaction{memo: "Miete", amount: -95_000, date: ~D[2026-12-01]}] = entered(c.giro)
    assert Repo.reload!(scheduled).next_date == ~D[2027-01-01]
  end

  test "one that happens once is gone once entered; the transaction keeps its date", c do
    scheduled = scheduled_fixture(c, frequency: :once)

    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-05]) == {:ok, 1}
    refute Repo.reload(scheduled)

    assert [%Transaction{scheduled_transaction_id: nil, scheduled_date: ~D[2026-12-01]}] =
             entered(c.giro)
  end

  test "a split is entered with its parts, a transfer with its counterpart", c do
    savings = account_fixture(name: "Sparkonto", kind: :savings)
    groceries = category_fixture(name: "Lebensmittel")

    scheduled_fixture(c,
      payee_id: nil,
      category_id: nil,
      amount: -100_000,
      subtransactions: [
        %{amount: -95_000, category_id: c.rent.id, payee_id: c.landlord.id},
        %{amount: -5_000, category_id: groceries.id, memo: "Nebenkosten"}
      ]
    )

    scheduled_fixture(c, payee_id: savings.transfer_payee.id, category_id: nil, amount: -20_000)

    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-01]) == {:ok, 2}

    split = Enum.find(entered(c.giro), &(&1.amount == -100_000))

    assert [%{amount: -95_000, category_id: rent_id}, %{amount: -5_000, memo: "Nebenkosten"}] =
             split.subtransactions

    assert rent_id == c.rent.id
    assert [%Transaction{amount: 20_000, transfer_transaction_id: id}] = entered(savings)
    assert id == Enum.find(entered(c.giro), &(&1.amount == -20_000)).id
  end

  test "one the Ledger refuses stays due and is reported; the others are entered", c do
    depot = account_fixture(name: "Depot", kind: :tracking)
    refused = scheduled_fixture(c, account_id: depot.id)
    scheduled_fixture(c, [])

    assert {:error, 1, [reason]} = Scheduled.enter_due(budget_scope(), ~D[2026-12-01])
    assert reason =~ "scheduled transaction #{refused.id} on 2026-12-01"
    assert reason =~ "category_id"
    assert Repo.reload!(refused).next_date == ~D[2026-12-01]
    assert entered(depot) == []
    assert [_rent] = entered(c.giro)
  end

  test "the daily job enters the budget owner's due ones", c do
    fix_now(~U[2026-12-01 10:00:00.000000Z])
    scheduled_fixture(c, [])

    assert Scheduled.Job.run() == :ok
    assert [%Transaction{date: ~D[2026-12-01]}] = entered(c.giro)
  end
end

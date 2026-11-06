defmodule Abakus.Ledger.ScheduledTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Ecto.Query

  alias Abakus.{Ids, Ledger, Repo}

  alias Abakus.Ledger.{
    Payee,
    Scheduled,
    ScheduledSubtransaction,
    ScheduledTransaction,
    Transaction
  }

  alias Abakus.Sync.Message

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
        repeat_unit: :month,
        repeat_every: 1,
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

  test "monthly steps keep the month's last day", c do
    scheduled = scheduled_fixture(c, next_date: ~D[2027-01-31])

    assert Scheduled.enter_due(budget_scope(), ~D[2027-03-28]) == {:ok, 3}

    assert Enum.map(entered(c.giro), & &1.date) == [
             ~D[2027-01-31],
             ~D[2027-02-28],
             ~D[2027-03-28]
           ]

    assert Repo.reload!(scheduled).next_date == ~D[2027-04-28]
  end

  test "steps every 2 weeks", c do
    scheduled =
      scheduled_fixture(c, next_date: ~D[2026-12-09], repeat_unit: :week, repeat_every: 2)

    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-23]) == {:ok, 2}
    assert Enum.map(entered(c.giro), & &1.date) == [~D[2026-12-09], ~D[2026-12-23]]
    assert Repo.reload!(scheduled).next_date == ~D[2027-01-06]
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

  test "one that happens once is deleted once entered, and not entered again", c do
    scheduled = scheduled_fixture(c, repeat_unit: nil, repeat_every: nil)

    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-05]) == {:ok, 1}
    assert Repo.reload(scheduled).deleted_at
    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-06]) == {:ok, 0}

    assert [%Transaction{scheduled_transaction_id: id, scheduled_date: ~D[2026-12-01]}] =
             entered(c.giro)

    assert id == scheduled.id
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

  test "one in a closed account waits as it is, and is caught up once the account is reopened",
       c do
    scheduled = scheduled_fixture(c, next_date: ~D[2026-10-01])
    {:ok, closed} = Ledger.update_account(budget_scope(), c.giro, %{closed: true})

    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-01]) == {:ok, 0}
    assert entered(c.giro) == []
    assert Repo.reload!(scheduled).next_date == ~D[2026-10-01]

    {:ok, _reopened} = Ledger.update_account(budget_scope(), closed, %{closed: false})

    assert Scheduled.enter_due(budget_scope(), ~D[2026-12-01]) == {:ok, 3}

    assert Enum.map(entered(c.giro), & &1.date) == [
             ~D[2026-10-01],
             ~D[2026-11-01],
             ~D[2026-12-01]
           ]

    assert Repo.reload!(scheduled).next_date == ~D[2027-01-01]
  end

  describe "a scheduled transaction changed after the due ones are listed" do
    # The change lands between listing the due ones and entering them.
    defp while_listing_due(change) do
      handler = make_ref()

      :telemetry.attach(
        handler,
        [:abakus, :repo, :query],
        fn
          _event, _measurements, %{source: "scheduled_transactions"}, _config ->
            :telemetry.detach(handler)
            change.()

          _event, _measurements, _metadata, _config ->
            :ok
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      Scheduled.enter_due(budget_scope(), ~D[2026-12-01])
    end

    test "is not entered once deleted", c do
      scheduled = scheduled_fixture(c, [])

      assert while_listing_due(fn -> {:ok, _} = Scheduled.delete(budget_scope(), scheduled) end) ==
               {:ok, 0}

      assert entered(c.giro) == []
    end

    test "is entered as it is then", c do
      scheduled = scheduled_fixture(c, [])

      assert while_listing_due(fn ->
               {:ok, _} = Scheduled.update(budget_scope(), scheduled, %{memo: "Neu"})
             end) == {:ok, 1}

      assert [%Transaction{memo: "Neu"}] = entered(c.giro)
    end
  end

  test "the daily job enters the budget owner's due ones", c do
    fix_now(~U[2026-12-01 10:00:00.000000Z])
    scheduled_fixture(c, [])

    assert Scheduled.Job.run() == :ok
    assert [%Transaction{date: ~D[2026-12-01]}] = entered(c.giro)
  end

  defp other_scope, do: Abakus.UsersFixtures.user_scope_fixture()

  defp attrs(c, attrs) do
    defaults = %{
      account_id: c.giro.id,
      next_date: ~D[2026-12-01],
      repeat_unit: :month,
      repeat_every: 1,
      payee_name: "Vermieter",
      category_id: c.rent.id,
      amount: -95_000
    }

    defaults
    |> Map.drop(if Keyword.has_key?(attrs, :payee_id), do: [:payee_name], else: [])
    |> Map.merge(Map.new(attrs))
  end

  describe "list/3" do
    test "lists an account's or every account's by next date, without deleted ones", c do
      savings = account_fixture(name: "Sparkonto", kind: :savings)
      later = scheduled_fixture(c, next_date: ~D[2027-01-01])
      sooner = scheduled_fixture(c, next_date: ~D[2026-11-15])
      saving = scheduled_fixture(c, account_id: savings.id, category_id: nil, payee_id: nil)
      gone = scheduled_fixture(c, [])
      {:ok, _} = Scheduled.delete(budget_scope(), gone)

      assert Enum.map(Scheduled.list(budget_scope(), c.giro), & &1.id) == [sooner.id, later.id]

      assert Enum.map(Scheduled.list(budget_scope(), :all), & &1.id) ==
               [sooner.id, saving.id, later.id]

      assert Enum.map(
               Scheduled.list(budget_scope(), :all, without_accounts: [c.giro.id]),
               & &1.id
             ) ==
               [saving.id]

      assert [%{payee: %Payee{name: "Vermieter"}, category: %{name: "Miete"}} | _] =
               Scheduled.list(budget_scope(), c.giro)

      assert Scheduled.list(other_scope(), :all) == []
    end
  end

  describe "get/2" do
    test "gets the user's with payees and parts; nil for another user's, a deleted one and no id",
         c do
      scheduled = scheduled_fixture(c, [])

      assert %ScheduledTransaction{payee: %Payee{name: "Vermieter"}, subtransactions: []} =
               Scheduled.get(budget_scope(), scheduled.id)

      assert Scheduled.get(other_scope(), scheduled.id) == nil
      assert Scheduled.get(budget_scope(), "kein-id") == nil

      {:ok, _} = Scheduled.delete(budget_scope(), scheduled)
      assert Scheduled.get(budget_scope(), scheduled.id) == nil
    end
  end

  describe "create/2" do
    test "creates it, naming the payee", c do
      assert {:ok, scheduled} =
               Scheduled.create(budget_scope(), attrs(c, repeat_unit: :week, repeat_every: 2))

      assert %ScheduledTransaction{
               next_date: ~D[2026-12-01],
               repeat_unit: :week,
               repeat_every: 2,
               amount: -95_000,
               cleared: :uncleared
             } = scheduled

      assert scheduled.payee_id == c.landlord.id
      assert [%{id: id}] = Scheduled.list(budget_scope(), c.giro)
      assert id == scheduled.id
    end

    test "creates a split with its parts and a transfer", c do
      savings = account_fixture(name: "Sparkonto", kind: :savings)

      assert {:ok, split} =
               Scheduled.create(
                 budget_scope(),
                 attrs(c,
                   payee_name: "",
                   category_id: nil,
                   amount: -100_000,
                   subtransactions: [
                     %{amount: -95_000, category_id: c.rent.id, payee_name: "Vermieter"},
                     %{amount: -5_000, payee_id: savings.transfer_payee.id, memo: "Rücklage"}
                   ]
                 )
               )

      assert [%{amount: -95_000, payee_id: landlord}, %{amount: -5_000, memo: "Rücklage"}] =
               Repo.preload(split, :subtransactions).subtransactions

      assert landlord == c.landlord.id

      assert {:ok, transfer} =
               Scheduled.create(
                 budget_scope(),
                 attrs(c, payee_id: savings.transfer_payee.id, category_id: nil)
               )

      assert transfer.payee_id == savings.transfer_payee.id
    end

    test "refuses what could not be entered, and creates no payee then", c do
      depot = account_fixture(name: "Depot", kind: :tracking)
      savings = account_fixture(name: "Sparkonto", kind: :savings)

      refused = fn attrs ->
        assert {:error, changeset} = Scheduled.create(budget_scope(), attrs(c, attrs))
        errors_on(changeset)
      end

      assert %{category_id: ["muss in einem Tracking-Konto leer sein"]} =
               refused.(account_id: depot.id, payee_name: "Neu")

      assert %{category_id: ["muss bei einer Umbuchung zwischen Budget-Konten leer sein"]} =
               refused.(payee_id: savings.transfer_payee.id)

      assert %{
               category_id: [
                 "muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"
               ]
             } =
               refused.(payee_id: depot.transfer_payee.id, category_id: nil)

      assert %{payee_id: ["wird im Budgetkonto geplant"]} =
               refused.(
                 account_id: depot.id,
                 payee_id: c.giro.transfer_payee.id,
                 category_id: nil
               )

      assert %{payee_id: ["darf nicht das eigene Konto sein"]} =
               refused.(payee_id: c.giro.transfer_payee.id, category_id: nil)

      assert %{repeat_every: ["must be less than or equal to 99"]} = refused.(repeat_every: 100)
      assert %{next_date: ["can't be blank"]} = refused.(next_date: nil)

      assert %{subtransactions: [%{category_id: ["muss in einem Tracking-Konto leer sein"]}, %{}]} =
               refused.(
                 account_id: depot.id,
                 payee_name: nil,
                 category_id: nil,
                 subtransactions: [
                   %{amount: -90_000, category_id: c.rent.id},
                   %{amount: -5_000}
                 ]
               )

      refute Repo.get_by(Payee, name: "Neu")
      assert Scheduled.list(budget_scope(), :all) == []
    end

    test "refuses a transfer to the Kasse account, as a whole and as a part", c do
      shared = account_fixture(name: "Kasse", kind: :checking, shared_expenses: true)
      refused = ["Das Kasse-Konto nimmt keine geplanten Buchungen an."]

      assert {:error, changeset} =
               Scheduled.create(
                 budget_scope(),
                 attrs(c, payee_id: shared.transfer_payee.id, category_id: nil)
               )

      assert %{payee_id: ^refused} = errors_on(changeset)

      assert {:error, changeset} =
               Scheduled.create(
                 budget_scope(),
                 attrs(c,
                   category_id: nil,
                   amount: -100_000,
                   subtransactions: [
                     %{amount: -95_000, category_id: c.rent.id},
                     %{amount: -5_000, payee_id: shared.transfer_payee.id}
                   ]
                 )
               )

      assert %{subtransactions: [%{}, %{payee_id: ^refused}]} = errors_on(changeset)
      assert Scheduled.list(budget_scope(), :all) == []
    end

    test "refuses another user's account, payee and category", c do
      theirs = other_scope()
      {:ok, account} = Ledger.create_account(theirs, %{name: "Fremd", kind: :checking})
      {:ok, payee} = Ledger.create_payee(theirs, %{name: "Fremder"})

      assert {:error, changeset} =
               Scheduled.create(budget_scope(), attrs(c, account_id: account.id))

      assert %{account_id: ["does not exist"]} = errors_on(changeset)

      assert {:error, changeset} =
               Scheduled.create(budget_scope(), attrs(c, payee_id: payee.id))

      assert %{payee_id: ["does not exist"]} = errors_on(changeset)

      assert {:error, changeset} =
               Scheduled.create(theirs, attrs(c, account_id: account.id, payee_name: nil))

      assert %{category_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "update/3" do
    test "changes it and writes both repeat fields with one clock", c do
      scheduled = scheduled_fixture(c, [])
      cursor = Repo.one(from m in Message, select: max(m.id)) || 0

      assert {:ok, %{repeat_unit: :month, repeat_every: 3, memo: "Neu"}} =
               Scheduled.update(budget_scope(), scheduled, %{repeat_every: 3, memo: "Neu"})

      messages =
        Repo.all(
          from m in Message,
            where: m.id > ^cursor and m.row_id == ^scheduled.id,
            select: {m.column, m.value, m.clock}
        )

      assert [
               {"memo", ~s("Neu"), clock},
               {"repeat_every", "3", clock},
               {"repeat_unit", ~s("month"), clock}
             ] = Enum.sort(messages)
    end

    test "tombstones the parts it removes", c do
      {:ok, split} =
        Scheduled.create(
          budget_scope(),
          attrs(c,
            category_id: nil,
            amount: -100_000,
            subtransactions: [%{amount: -95_000}, %{amount: -5_000}]
          )
        )

      [kept, removed] = Repo.preload(split, :subtransactions).subtransactions

      assert {:ok, _} =
               Scheduled.update(budget_scope(), split, %{
                 amount: -95_000,
                 category_id: c.rent.id,
                 subtransactions: []
               })

      assert Repo.reload!(kept).deleted_at
      assert Repo.reload!(removed).deleted_at
      assert Repo.aggregate(ScheduledSubtransaction, :count) == 2
    end

    test "refuses a deleted one", c do
      scheduled = scheduled_fixture(c, [])
      {:ok, _} = Scheduled.delete(budget_scope(), scheduled)

      assert Scheduled.update(budget_scope(), scheduled, %{memo: "x"}) == {:error, :not_found}

      assert Scheduled.update(other_scope(), scheduled_fixture(c, []), %{}) ==
               {:error, :not_found}
    end
  end

  describe "delete/2" do
    test "tombstones it", c do
      scheduled = scheduled_fixture(c, [])

      assert {:ok, _} = Scheduled.delete(budget_scope(), scheduled)
      assert Repo.reload!(scheduled).deleted_at
      assert Scheduled.delete(budget_scope(), scheduled) == {:error, :not_found}
    end
  end

  describe "enter_now/2" do
    test "enters the next occurrence approved, with the job's id, and moves on", c do
      scheduled = scheduled_fixture(c, next_date: ~D[2026-12-01])

      assert {:ok, _} = Scheduled.enter_now(budget_scope(), scheduled)

      assert [%Transaction{date: ~D[2026-12-01], approved: true, source: :scheduled} = entered] =
               entered(c.giro)

      assert entered.id == Ids.entered_transaction(scheduled.id, ~D[2026-12-01])
      assert Repo.reload!(scheduled).next_date == ~D[2027-01-01]

      assert Scheduled.enter_due(budget_scope(), ~D[2026-12-01]) == {:ok, 0}
      assert [_once] = entered(c.giro)
    end

    test "an occurrence entered already moves on without a second one", c do
      scheduled = scheduled_fixture(c, next_date: ~D[2026-12-01])
      assert Scheduled.enter_due(budget_scope(), ~D[2026-12-01]) == {:ok, 1}

      scheduled
      |> Repo.reload!()
      |> Ecto.Changeset.change(next_date: ~D[2026-12-01])
      |> Repo.update!()

      assert {:ok, _} = Scheduled.enter_now(budget_scope(), scheduled)
      assert [_once] = entered(c.giro)
      assert Repo.reload!(scheduled).next_date == ~D[2027-01-01]
    end

    test "deletes one that happens once", c do
      scheduled = scheduled_fixture(c, repeat_unit: nil, repeat_every: nil)

      assert {:ok, _} = Scheduled.enter_now(budget_scope(), scheduled)
      assert Repo.reload!(scheduled).deleted_at
      assert [_entered] = entered(c.giro)
    end
  end

  describe "skip/2" do
    test "moves on without entering; one that happens once goes", c do
      monthly = scheduled_fixture(c, next_date: ~D[2027-01-31])
      once = scheduled_fixture(c, repeat_unit: nil, repeat_every: nil)

      assert {:ok, _} = Scheduled.skip(budget_scope(), monthly)
      assert Repo.reload!(monthly).next_date == ~D[2027-02-28]

      assert {:ok, _} = Scheduled.skip(budget_scope(), once)
      assert Repo.reload!(once).deleted_at
      assert entered(c.giro) == []
    end
  end
end

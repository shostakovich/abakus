defmodule Abakus.Kasse.ReimbursementLinkTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.KasseFixtures

  alias Abakus.Kasse.{Balances, BudgetLink, Expenses, Participants}
  alias Abakus.Kasse.BudgetLink.Link
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Ledger
  alias Abakus.Ledger.Transaction
  alias Abakus.Users.Scope

  setup do
    anna = person!("Anna").id
    ben = person!("Ben").id
    shared = account_fixture(%{name: "Shared", kind: :cash})
    checking = account_fixture(%{name: "Checking", kind: :checking})
    {:ok, _created} = BudgetLink.switch_on(scope_of(anna), shared.id)

    %{anna: anna, ben: ben, shared: shared, checking: checking}
  end

  defp live(account),
    do:
      Repo.all(
        from t in Transaction,
          where: t.account_id == ^account.id and is_nil(t.deleted_at),
          order_by: t.id
      )

  defp led(expense),
    do:
      Repo.one(
        from t in Transaction, where: t.kasse_expense_id == ^expense.id and is_nil(t.deleted_at)
      )

  defp reimbursements,
    do:
      Repo.all(
        from e in Expense, where: e.reimbursement and is_nil(e.deleted_at), preload: :shares
      )

  defp transfer(c, attrs, opts \\ []) do
    attrs =
      Enum.into(attrs, %{
        account_id: c.checking.id,
        date: ~D[2026-10-12],
        payee_id: c.shared.transfer_payee.id
      })

    BudgetLink.write_from_register(budget_scope(), nil, attrs, opts)
  end

  defp balances_agree(c) do
    assert Ledger.balances(budget_scope())[c.shared.id].balance ==
             Balances.balance(scope_of(c.anna))
  end

  describe "scenario: a reimbursement entered in the Kasse" do
    test "is a transfer from the chosen account to the shared-expenses account", c do
      payback =
        create_with!(reimbursement(3000, "2026-10-12", c.anna, c.ben), c.anna,
          budget_account_id: c.checking.id
        )

      assert [%{amount: -3000, payee_id: to_shared} = checking] = live(c.checking)
      assert to_shared == c.shared.transfer_payee.id
      assert [%{amount: 3000, category_id: nil} = shared] = live(c.shared)
      assert shared.id == led(payback).id
      assert shared.transfer_transaction_id == checking.id
      assert Ledger.led_by(budget_scope(), checking) == {:kasse_expense, payback.id}
      balances_agree(c)
    end
  end

  describe "scenario: a transfer in the register becomes a reimbursement" do
    test "creates a reimbursement from the owner to the other person", c do
      assert {:ok, transaction} = transfer(c, amount: -3000)

      assert [%Expense{paid_by_id: anna, amount_cents: 3000, shares: [share]} = payback] =
               reimbursements()

      assert {anna, share.participant_id, payback.date} == {c.anna, c.ben, ~D[2026-10-12]}
      assert Ledger.led_by(budget_scope(), transaction) == {:kasse_expense, payback.id}
      assert led(payback).id == transaction.transfer_transaction_id
      assert length(live(c.shared)) == 1
      balances_agree(c)
    end

    test "money from the shared-expenses account is a reimbursement to the owner", c do
      {:ok, _transaction} = transfer(c, amount: 2500)

      assert [%Expense{paid_by_id: ben, amount_cents: 2500, shares: [share]}] = reimbursements()
      assert {ben, share.participant_id} == {c.ben, c.anna}
      balances_agree(c)
    end

    test "asks for the person while the group has several others", c do
      cleo = person!("Cleo").id

      assert {:error, "Bitte wählen, mit wem in der Kasse die Rückzahlung ist."} =
               transfer(c, amount: -3000)

      assert live(c.checking) == []

      assert BudgetLink.reimbursement_people(budget_scope()).people |> Enum.map(& &1.id) == [
               c.ben,
               cleo
             ]

      assert {:ok, _transaction} = transfer(c, [amount: -3000], person_id: cleo)
      assert [%Expense{shares: [%{participant_id: ^cleo}]}] = reimbursements()
    end

    test "dated before the link's start date it creates nothing", c do
      Repo.update!(Ecto.Changeset.change(Repo.get!(Link, c.anna), start_date: ~D[2026-10-01]))

      assert {:ok, _transaction} = transfer(c, amount: -3000, date: ~D[2026-09-30])
      assert reimbursements() == []

      assert {:ok, _transaction} = transfer(c, amount: -3000, date: ~D[2026-10-01])
      assert [_payback] = reimbursements()
    end

    test "a transaction that becomes such a transfer becomes a reimbursement once", c do
      {:ok, purchase} =
        BudgetLink.write_from_register(budget_scope(), nil, %{
          account_id: c.checking.id,
          date: ~D[2026-10-12],
          amount: -3000
        })

      assert reimbursements() == []

      {:ok, transfer} =
        BudgetLink.write_from_register(budget_scope(), purchase, %{
          payee_id: c.shared.transfer_payee.id
        })

      assert [_payback] = reimbursements()

      {:ok, _memo} =
        BudgetLink.write_from_register(budget_scope(), transfer, %{memo: "Thanks"})

      assert [_payback] = reimbursements()
    end

    test "a transfer that cannot be a reimbursement is refused", c do
      refused =
        "Eine Umbuchung mit „Shared“ wird eine Rückzahlung in der Kasse und geht deshalb nur als " <>
          "ganze Buchung mit einem offenen Budget-Konto."

      tracking = account_fixture(%{kind: :tracking})
      closed = account_fixture(%{kind: :savings, closed: true})
      category = category_fixture()

      assert {:error, ^refused} =
               transfer(c,
                 account_id: tracking.id,
                 amount: -3000,
                 counterpart_category_id: category.id
               )

      assert {:error, ^refused} = transfer(c, account_id: closed.id, amount: -3000)

      assert {:error, ^refused} =
               transfer(c,
                 amount: -3000,
                 payee_id: nil,
                 subtransactions: [
                   %{amount: -1000, category_id: category.id},
                   %{amount: -2000, payee_id: c.shared.transfer_payee.id}
                 ]
               )

      assert live(c.shared) == [] and reimbursements() == []
    end

    test "is refused while the owner's person is archived", c do
      {:ok, _archived} =
        Participants.archive_participant(
          Scope.system(),
          Participants.get_participant!(Scope.system(), c.anna)
        )

      assert {:error,
              "Deine Person in der Kasse ist archiviert, deshalb kann eine Umbuchung mit „Shared“ " <>
                "keine Rückzahlung werden."} = transfer(c, amount: -3000)

      assert live(c.checking) == [] and reimbursements() == []
    end

    test "before the link's start date such a transfer creates nothing", c do
      Repo.update!(Ecto.Changeset.change(Repo.get!(Link, c.anna), start_date: ~D[2026-10-01]))
      tracking = account_fixture(%{kind: :tracking})

      assert {:ok, _transfer} =
               transfer(c,
                 account_id: tracking.id,
                 amount: -3000,
                 date: ~D[2026-09-30],
                 counterpart_category_id: category_fixture().id
               )

      assert reimbursements() == []
    end
  end

  describe "scenario: a reimbursement the other participant records" do
    setup c do
      payback = create!(reimbursement(2500, "2026-10-12", c.ben, c.anna), c.ben)
      %{payback: payback}
    end

    test "needs an account until the owner chooses one", c do
      assert [%{amount: -2500, transfer_transaction_id: nil, category_id: nil} = open] =
               live(c.shared)

      assert Repo.preload(open, :payee).payee.name == "Rückzahlung"
      assert live(c.checking) == []
      balances_agree(c)

      {:ok, _payback} =
        Expenses.update_expense(scope_of(c.anna), c.payback, Expenses.input(c.payback),
          budget_account_id: c.checking.id
        )

      assert [%{id: id, amount: -2500, payee_id: to_checking}] = live(c.shared)
      assert {id, to_checking} == {open.id, c.checking.transfer_payee.id}
      assert [%{amount: 2500} = counterpart] = live(c.checking)

      [bank_line] =
        Ledger.find_matches(budget_scope(), c.checking, :file, [
          %{date: ~D[2026-10-14], amount: 2500}
        ])

      assert bank_line.id == counterpart.id
      balances_agree(c)
    end

    test "a bank line accepted as its counterpart's match leaves it led by the Kasse", c do
      {:ok, payback} =
        Expenses.update_expense(scope_of(c.anna), c.payback, Expenses.input(c.payback),
          budget_account_id: c.checking.id
        )

      [counterpart] = live(c.checking)

      {:ok, proposal} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.checking.id,
          date: ~D[2026-10-14],
          amount: 2500,
          source: :file,
          matched_transaction_id: counterpart.id
        })

      assert {:ok, matched} = Ledger.accept_match(budget_scope(), proposal)
      assert [%{id: id, date: ~D[2026-10-12], amount: 2500}] = live(c.checking)
      assert id == counterpart.id
      assert Ledger.led_by(budget_scope(), matched) == {:kasse_expense, payback.id}
      balances_agree(c)

      {:ok, _payback} =
        Expenses.update_expense(scope_of(c.ben), payback, %{
          Expenses.input(payback)
          | amount_cents: 2000
        })

      assert [%{id: ^id, amount: 2000}] = live(c.checking)
      balances_agree(c)
    end

    test "drops a category the register gave it once it gets an account", c do
      {:ok, _categorised} =
        Ledger.update_transaction(budget_scope(), led(c.payback), %{
          category_id: category_fixture().id
        })

      assert {:ok, _payback} =
               Expenses.update_expense(scope_of(c.anna), c.payback, Expenses.input(c.payback),
                 budget_account_id: c.checking.id
               )

      assert [%{category_id: nil, payee_id: to_checking}] = live(c.shared)
      assert to_checking == c.checking.transfer_payee.id
      balances_agree(c)
    end

    test "keeps its account when someone else saves it", c do
      {:ok, payback} =
        Expenses.update_expense(scope_of(c.anna), c.payback, Expenses.input(c.payback),
          budget_account_id: c.checking.id
        )

      {:ok, _payback} =
        Expenses.update_expense(scope_of(c.ben), payback, %{
          Expenses.input(payback)
          | amount_cents: 2000
        })

      assert [%{amount: -2000, payee_id: to_checking}] = live(c.shared)
      assert to_checking == c.checking.transfer_payee.id
      assert [%{amount: 2000}] = live(c.checking)

      {:ok, _deleted} = Expenses.delete_expense(scope_of(c.ben), payback)
      assert live(c.shared) == [] and live(c.checking) == []
    end

    test "stays as it is while the owner has reconciled its counterpart", c do
      {:ok, payback} =
        Expenses.update_expense(scope_of(c.anna), c.payback, Expenses.input(c.payback),
          budget_account_id: c.checking.id
        )

      [counterpart] = live(c.checking)
      Repo.update!(Ecto.Changeset.change(counterpart, cleared: :reconciled))

      message =
        "Die Rückzahlung ist im Budget im Konto „Checking“ abgeglichen und muss zuerst dort geändert werden."

      assert {:error, changeset} =
               Expenses.update_expense(scope_of(c.ben), payback, %{
                 Expenses.input(payback)
                 | amount_cents: 2000
               })

      assert [budget: {^message, []}] = changeset.errors
      assert {:error, changeset} = Expenses.delete_expense(scope_of(c.ben), payback)
      assert [budget: {^message, []}] = changeset.errors

      assert [%{amount: 2500, cleared: :reconciled}] = live(c.checking)
      assert Repo.reload!(payback).amount_cents == 2500
      balances_agree(c)
    end

    test "a transfer in the register completes it instead of creating another", c do
      open = led(c.payback)

      assert {:ok, transaction} = transfer(c, amount: 2500, date: ~D[2026-10-15])

      assert [payback] = reimbursements()
      assert payback.id == c.payback.id
      assert Repo.reload!(open).deleted_at

      assert [%{id: shared_id, amount: -2500, date: ~D[2026-10-12]}] = live(c.shared)
      assert shared_id == transaction.transfer_transaction_id
      assert led(payback).id == shared_id
      assert [%{amount: 2500, date: ~D[2026-10-12]}] = live(c.checking)
      balances_agree(c)
    end

    test "only within the match window and with the same amount", c do
      {:ok, _later} = transfer(c, amount: 2500, date: ~D[2026-10-23])
      {:ok, _other} = transfer(c, amount: 2400)

      assert length(reimbursements()) == 3
      assert %{transfer_transaction_id: nil} = led(c.payback)
    end
  end

  test "refuses an account that is no budget account of the owner", c do
    tracking = account_fixture(%{kind: :tracking})

    assert {:error, changeset} =
             Expenses.create_expense(
               scope_of(c.anna),
               reimbursement(3000, "2026-10-12", c.anna, c.ben),
               budget_account_id: tracking.id
             )

    assert [budget: {"Das Konto für die Rückzahlung gibt es im Budget nicht.", []}] =
             changeset.errors
  end

  test "a reimbursement between others gives no transaction", c do
    cleo = person!("Cleo").id
    create!(reimbursement(3000, "2026-10-12", c.ben, cleo), c.ben)
    assert live(c.shared) == []
  end

  defp create_with!(attrs, actor, opts) do
    {:ok, expense} = Expenses.create_expense(scope_of(actor), attrs, opts)
    expense
  end
end

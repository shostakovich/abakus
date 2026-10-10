defmodule Abakus.Ledger.TransactionsTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Payee, Subtransaction, Transaction, TransactionOrigin}

  defp attrs(account, attrs),
    do: Enum.into(attrs, %{account_id: account.id, date: ~D[2026-10-09], amount: -1_250})

  describe "create_transaction/1" do
    test "stores a transaction with YNAB's defaults" do
      account = account_fixture()
      payee = payee_fixture()
      category = category_fixture()

      assert {:ok, transaction} =
               Ledger.create_transaction(
                 attrs(account,
                   payee_id: payee.id,
                   category_id: category.id,
                   memo: "Wocheneinkauf"
                 )
               )

      assert %Transaction{
               amount: -1_250,
               cleared: :uncleared,
               approved: true,
               flag: nil,
               source: :manual,
               deleted_at: nil,
               memo: "Wocheneinkauf"
             } = Repo.get!(Transaction, transaction.id)
    end

    test "stores cleared state, approval, flag and source" do
      account = account_fixture()

      assert {:ok, transaction} =
               Ledger.create_transaction(
                 attrs(account,
                   cleared: "reconciled",
                   approved: true,
                   flag: "purple",
                   source: "file"
                 )
               )

      assert %Transaction{cleared: :reconciled, approved: true, flag: :purple, source: :file} =
               Repo.get!(Transaction, transaction.id)
    end

    test "approval defaults by source: manual entries are approved, imports are not" do
      account = account_fixture()
      approved = fn attrs -> transaction_fixture(attrs(account, attrs)).approved end

      assert approved.(source: :manual)
      refute approved.(source: :ynab)
      refute approved.(source: :file)
      refute approved.(source: :bank)
      refute approved.(source: :api)
      assert approved.(source: :ynab, approved: true)

      assert {:ok, %Transaction{approved: true}} =
               Ledger.create_transaction(%{
                 "account_id" => account.id,
                 "date" => "2026-10-09",
                 "amount" => "-1",
                 "source" => "file",
                 "approved" => "true"
               })

      refute approved.(source: :manual, approved: false)
    end

    test "the source is set once" do
      transaction = transaction_fixture(source: :bank)

      assert {:ok, %Transaction{source: :bank}} =
               Ledger.update_transaction(transaction, %{source: :manual, memo: "x"})
    end

    test "requires account, date and amount" do
      assert {:error, changeset} = Ledger.create_transaction(%{})

      assert %{
               account_id: ["can't be blank"],
               date: ["can't be blank"],
               amount: ["can't be blank"]
             } =
               errors_on(changeset)
    end

    test "rejects unknown enum values" do
      account = account_fixture()

      assert {:error, changeset} =
               Ledger.create_transaction(
                 attrs(account, cleared: "pending", flag: "pink", source: "csv")
               )

      assert %{cleared: ["is invalid"], flag: ["is invalid"], source: ["is invalid"]} =
               errors_on(changeset)
    end

    test "amounts are whole cents" do
      account = account_fixture()

      assert {:error, changeset} = Ledger.create_transaction(attrs(account, amount: 12.5))
      assert %{amount: ["is invalid"]} = errors_on(changeset)
      assert {:error, changeset} = Ledger.create_transaction(attrs(account, amount: "12.50"))
      assert %{amount: ["is invalid"]} = errors_on(changeset)

      assert {:ok, %Transaction{amount: 1_250}} =
               Ledger.create_transaction(attrs(account, amount: "1250"))
    end

    test "amounts are at most 100 billion euros either way" do
      account = account_fixture()
      max = 10_000_000_000_000

      assert {:ok, _} = Ledger.create_transaction(attrs(account, amount: max))
      assert {:ok, _} = Ledger.create_transaction(attrs(account, amount: -max))

      for amount <- [2 ** 70, -(2 ** 70), max + 1] do
        assert {:error, changeset} = Ledger.create_transaction(attrs(account, amount: amount))
        assert %{amount: [message]} = errors_on(changeset)
        assert message =~ "100.000.000.000"
      end

      subtransactions = [%{amount: 2 ** 70}, %{amount: -(2 ** 70) - 1}]

      assert {:error, changeset} =
               Ledger.create_transaction(
                 attrs(account, amount: -1, subtransactions: subtransactions)
               )

      assert %{subtransactions: [%{amount: [_]}, %{amount: [_]}]} = errors_on(changeset)
    end

    test "the account must exist" do
      assert {:error, changeset} =
               Ledger.create_transaction(%{account_id: -1, date: ~D[2026-10-09], amount: 1})

      assert %{account_id: ["does not exist"]} = errors_on(changeset)
    end

    test "the payee and category must exist" do
      account = account_fixture()

      assert {:error, changeset} =
               Ledger.create_transaction(attrs(account, payee_id: -1, category_id: -2))

      assert %{payee_id: ["does not exist"], category_id: ["does not exist"]} =
               errors_on(changeset)

      subtransactions = [%{amount: -1_000, payee_id: -1}, %{amount: -250, category_id: -2}]

      assert {:error, changeset} =
               Ledger.create_transaction(attrs(account, subtransactions: subtransactions))

      assert %{
               subtransactions: [
                 %{payee_id: ["does not exist"]},
                 %{category_id: ["does not exist"]}
               ]
             } = errors_on(changeset)

      transaction = transaction_fixture(account_id: account.id)

      assert {:error, changeset} = Ledger.update_transaction(transaction, %{payee_id: -1})
      assert %{payee_id: ["does not exist"]} = errors_on(changeset)
    end

    test "remembers the category as the payee's last category" do
      account = account_fixture()
      payee = payee_fixture()
      groceries = category_fixture()
      household = category_fixture()

      transaction_fixture(account_id: account.id, payee_id: payee.id, category_id: groceries.id)
      assert Repo.get!(Payee, payee.id).last_category_id == groceries.id

      transaction_fixture(account_id: account.id, payee_id: payee.id)
      assert Repo.get!(Payee, payee.id).last_category_id == groceries.id

      transaction = transaction_fixture(account_id: account.id, payee_id: payee.id)
      assert {:ok, _} = Ledger.update_transaction(transaction, %{category_id: household.id})
      assert Repo.get!(Payee, payee.id).last_category_id == household.id
    end

    test "subtransactions remember their categories for their payees" do
      account = account_fixture()
      payee = payee_fixture()
      category = category_fixture()

      transaction_fixture(
        account_id: account.id,
        subtransactions: [
          %{amount: -1_000, payee_id: payee.id, category_id: category.id},
          %{amount: -250}
        ]
      )

      assert Repo.get!(Payee, payee.id).last_category_id == category.id
    end

    test "a deleted transaction cannot be changed" do
      transaction = transaction_fixture()
      {:ok, _} = Ledger.delete_transaction(transaction)

      assert {:error, changeset} = Ledger.update_transaction(transaction, %{memo: "zu spät"})
      assert %{deleted_at: ["Die Buchung ist gelöscht"]} = errors_on(changeset)
      assert Repo.get!(Transaction, transaction.id).memo == nil
    end
  end

  describe "category rule" do
    setup do
      %{
        checking: account_fixture(kind: :checking),
        savings: account_fixture(kind: :savings),
        depot: account_fixture(kind: :tracking),
        category: category_fixture()
      }
    end

    test "a transfer between budget accounts has no category", c do
      transfer = attrs(c.checking, payee_id: c.savings.transfer_payee.id)

      assert {:error, changeset} =
               Ledger.create_transaction(Map.put(transfer, :category_id, c.category.id))

      assert %{category_id: ["muss bei einer Umbuchung zwischen Budget-Konten leer sein"]} =
               errors_on(changeset)

      assert {:ok, _} = Ledger.create_transaction(transfer)
    end

    test "a transfer from a budget to a tracking account needs a category", c do
      transfer = attrs(c.checking, payee_id: c.depot.transfer_payee.id)

      assert {:error, changeset} = Ledger.create_transaction(transfer)

      assert %{
               category_id: [
                 "muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"
               ]
             } =
               errors_on(changeset)

      assert {:ok, _} = Ledger.create_transaction(Map.put(transfer, :category_id, c.category.id))
    end

    test "tracking accounts have no categories", c do
      assert {:error, changeset} =
               Ledger.create_transaction(attrs(c.depot, category_id: c.category.id))

      assert %{category_id: ["muss in einem Tracking-Konto leer sein"]} = errors_on(changeset)

      transfer =
        attrs(c.depot,
          payee_id: c.checking.transfer_payee.id,
          amount: 5_000,
          counterpart_category_id: c.category.id
        )

      assert {:ok, _} = Ledger.create_transaction(transfer)
    end

    test "other transactions in budget accounts may be uncategorised", c do
      assert {:ok, _} = Ledger.create_transaction(attrs(c.checking, payee_id: payee_fixture().id))
    end

    test "applies to subtransactions", c do
      subtransactions = [
        %{amount: -1_000, category_id: c.category.id},
        %{amount: -250, payee_id: c.depot.transfer_payee.id}
      ]

      assert {:error, changeset} =
               Ledger.create_transaction(attrs(c.checking, subtransactions: subtransactions))

      assert %{
               subtransactions: [
                 %{},
                 %{
                   category_id: [
                     "muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"
                   ]
                 }
               ]
             } =
               errors_on(changeset)

      subtransactions =
        List.replace_at(subtransactions, 1, %{amount: -250, payee_id: c.savings.transfer_payee.id})

      assert {:ok, _} =
               Ledger.create_transaction(attrs(c.checking, subtransactions: subtransactions))
    end

    test "applies on update", c do
      transaction = transaction_fixture(account_id: c.checking.id, category_id: c.category.id)

      assert {:error, changeset} =
               Ledger.update_transaction(transaction, %{payee_id: c.savings.transfer_payee.id})

      assert %{category_id: ["muss bei einer Umbuchung zwischen Budget-Konten leer sein"]} =
               errors_on(changeset)
    end

    test "is a pure function of the accounts", c do
      changeset = Transaction.changeset(%Transaction{}, attrs(c.checking, payee_id: 42))

      refute Transaction.validate_accounts(changeset, c.checking, %{42 => c.depot}).valid?
      assert Transaction.validate_accounts(changeset, c.checking, %{42 => c.savings}).valid?
      assert Transaction.validate_accounts(changeset, %Account{kind: :tracking}, %{}).valid?
      refute Transaction.validate_accounts(changeset, c.checking, %{42 => c.checking}).valid?
    end

    test "a split is no transfer as a whole", c do
      split =
        attrs(c.checking,
          payee_id: c.savings.transfer_payee.id,
          subtransactions: [%{amount: -1_000, category_id: c.category.id}, %{amount: -250}]
        )

      assert {:error, changeset} = Ledger.create_transaction(split)

      assert %{payee_id: ["darf bei einer Aufteilung keine Umbuchung sein"]} =
               errors_on(changeset)

      assert {:ok, _} = Ledger.create_transaction(Map.delete(split, :payee_id))
    end

    test "a split with categories cannot move to a tracking account", c do
      split =
        transaction_fixture(
          account_id: c.checking.id,
          subtransactions: [%{amount: -1_000, category_id: c.category.id}, %{amount: -250}]
        )

      assert {:error, changeset} = Ledger.update_transaction(split, %{account_id: c.depot.id})

      assert %{subtransactions: ["muss in einem Tracking-Konto leer sein"]} =
               errors_on(changeset)

      [first, second] = Repo.preload(split, :subtransactions).subtransactions

      assert {:error, changeset} =
               Ledger.update_transaction(split, %{
                 account_id: c.depot.id,
                 subtransactions: [%{id: first.id, memo: "Kino"}, %{id: second.id}]
               })

      assert %{subtransactions: [%{category_id: ["muss in einem Tracking-Konto leer sein"]}, %{}]} =
               errors_on(changeset)

      assert Repo.get!(Transaction, split.id).account_id == c.checking.id
    end

    test "a split moves to a tracking account without categories", c do
      categorised = [%{amount: -1_000, category_id: c.category.id}, %{amount: -250}]
      split = transaction_fixture(account_id: c.checking.id, subtransactions: categorised)

      assert {:ok, %Transaction{subtransactions: [_, _]}} =
               Ledger.update_transaction(split, %{
                 account_id: c.depot.id,
                 subtransactions: [%{amount: -1_000}, %{amount: -250}]
               })

      split = transaction_fixture(account_id: c.checking.id, subtransactions: categorised)

      assert {:ok, %Transaction{subtransactions: []}} =
               Ledger.update_transaction(split, %{account_id: c.depot.id, subtransactions: []})
    end
  end

  describe "splits" do
    setup do
      %{account: account_fixture(), groceries: category_fixture(), household: category_fixture()}
    end

    test "keep their order", c do
      subtransactions = Enum.map(1..3, &%{amount: -&1, memo: "#{&1}"})

      {:ok, split} =
        Ledger.create_transaction(attrs(c.account, amount: -6, subtransactions: subtransactions))

      [one, two, three] = split.subtransactions

      {:ok, _} =
        Ledger.update_transaction(split, %{
          amount: -10,
          subtransactions: [
            %{id: three.id},
            %{amount: -4, memo: "4"},
            %{id: one.id},
            %{id: two.id}
          ]
        })

      assert [%Transaction{subtransactions: subtransactions}] =
               Ledger.list_transactions(c.account)

      assert Enum.map(subtransactions, & &1.memo) == ["3", "4", "1", "2"]
      assert Enum.map(subtransactions, & &1.position) == [0, 1, 2, 3]
    end

    test "stores the subtransactions", c do
      subtransactions = [
        %{amount: -1_000, category_id: c.groceries.id, memo: "Essen"},
        %{amount: -250, category_id: c.household.id, payee_id: payee_fixture().id}
      ]

      assert {:ok, transaction} =
               Ledger.create_transaction(attrs(c.account, subtransactions: subtransactions))

      assert [%Subtransaction{amount: -1_000, memo: "Essen"}, %Subtransaction{amount: -250}] =
               Repo.all(
                 from s in Subtransaction,
                   where: s.transaction_id == ^transaction.id,
                   order_by: s.id
               )
    end

    test "need at least two subtransactions", c do
      subtransactions = [%{amount: -1_250, category_id: c.groceries.id}]

      assert {:error, changeset} =
               Ledger.create_transaction(attrs(c.account, subtransactions: subtransactions))

      assert %{subtransactions: ["braucht mindestens zwei Teile"]} = errors_on(changeset)
    end

    test "add up to the parent", c do
      subtransactions = [
        %{amount: -1_000, category_id: c.groceries.id},
        %{amount: -200, category_id: c.household.id}
      ]

      assert {:error, changeset} =
               Ledger.create_transaction(attrs(c.account, subtransactions: subtransactions))

      assert %{amount: ["muss der Summe der Teile entsprechen"]} = errors_on(changeset)
    end

    test "leave the parent without a category", c do
      subtransactions = [%{amount: -1_000}, %{amount: -250}]

      assert {:error, changeset} =
               Ledger.create_transaction(
                 attrs(c.account, category_id: c.groceries.id, subtransactions: subtransactions)
               )

      assert %{category_id: ["muss bei einer Aufteilung leer sein"]} = errors_on(changeset)
    end

    test "subtransactions need an amount", c do
      assert {:error, changeset} =
               Ledger.create_transaction(
                 attrs(c.account, subtransactions: [%{amount: -1_250}, %{memo: "?"}])
               )

      assert %{subtransactions: [%{}, %{amount: ["can't be blank"]}]} = errors_on(changeset)
    end

    test "any amounts that add up are accepted, any others are not", c do
      for _ <- 1..50 do
        subtransactions =
          Enum.map(1..Enum.random(2..6), fn _ -> %{amount: Enum.random(-100_000..100_000)} end)

        total = subtransactions |> Enum.map(& &1.amount) |> Enum.sum()

        assert {:ok, _} =
                 Ledger.create_transaction(
                   attrs(c.account, amount: total, subtransactions: subtransactions)
                 )

        off_by = Enum.random([-1, 1]) * Enum.random(1..1_000)

        assert {:error, _} =
                 Ledger.create_transaction(
                   attrs(c.account, amount: total + off_by, subtransactions: subtransactions)
                 )
      end
    end

    test "replacing the subtransactions deletes the old ones and checks the new sum", c do
      subtransactions = [%{amount: -1_000}, %{amount: -250}]

      {:ok, transaction} =
        Ledger.create_transaction(attrs(c.account, subtransactions: subtransactions))

      new_subtransactions = [%{amount: -600}, %{amount: -400}, %{amount: -250}]

      assert {:ok, _} =
               Ledger.update_transaction(transaction, %{subtransactions: new_subtransactions})

      assert Repo.aggregate(
               from(s in Subtransaction, where: s.transaction_id == ^transaction.id),
               :count
             ) == 3

      assert {:error, changeset} = Ledger.update_transaction(transaction, %{amount: -1_000})
      assert %{amount: ["muss der Summe der Teile entsprechen"]} = errors_on(changeset)
    end

    test "go with the parent row", c do
      subtransactions = [%{amount: -1_000}, %{amount: -250}]

      {:ok, transaction} =
        Ledger.create_transaction(attrs(c.account, subtransactions: subtransactions))

      Repo.delete!(transaction)
      assert Repo.aggregate(Subtransaction, :count) == 0
    end
  end

  describe "delete_transaction/1" do
    test "soft-deletes the transaction" do
      account = account_fixture()
      transaction = transaction_fixture(account_id: account.id)
      other = transaction_fixture(account_id: account.id)

      assert {:ok, %Transaction{deleted_at: %DateTime{}}} = Ledger.delete_transaction(transaction)
      assert Enum.map(Ledger.list_transactions(account), & &1.id) == [other.id]
    end

    test "deleting a deleted transaction changes nothing" do
      transaction = transaction_fixture()
      {:ok, deleted} = Ledger.delete_transaction(transaction)

      assert {:ok, again} = Ledger.delete_transaction(transaction)
      assert again.deleted_at == deleted.deleted_at
      assert again.updated_at == deleted.updated_at
    end
  end

  describe "delete_transactions/2" do
    test "deletes every transaction, or none when one is refused" do
      account = account_fixture()
      first = transaction_fixture(account_id: account.id)
      second = transaction_fixture(account_id: account.id)
      reconciled = transaction_fixture(account_id: account.id, cleared: :reconciled)

      assert {:error, %Ecto.Changeset{}} = Ledger.delete_transactions([first, reconciled])
      refute Repo.get!(Transaction, first.id).deleted_at

      assert {:ok, [_, _]} =
               Ledger.delete_transactions([first, reconciled], reconciled: :confirmed)

      assert Enum.map(Ledger.list_transactions(account), & &1.id) == [second.id]
    end
  end

  test "last_transfer_category_id/2 finds the category last used on a transfer with the account" do
    giro = account_fixture()
    depot = account_fixture(kind: :tracking)
    old = category_fixture()
    newer = category_fixture()
    payee_id = depot.transfer_payee.id

    assert Ledger.last_transfer_category_id(giro.id, payee_id) == nil

    transaction_fixture(
      account_id: giro.id,
      date: ~D[2026-09-01],
      amount: -100,
      payee_id: payee_id,
      category_id: old.id
    )

    assert Ledger.last_transfer_category_id(giro.id, payee_id) == old.id

    transaction_fixture(
      account_id: giro.id,
      date: ~D[2026-10-01],
      amount: -300,
      subtransactions: [
        %{amount: -200, payee_id: payee_id, category_id: newer.id},
        %{amount: -100}
      ]
    )

    assert Ledger.last_transfer_category_id(giro.id, payee_id) == newer.id
  end

  test "list_transactions/1 lists newest first with subtransactions" do
    account = account_fixture()
    older = transaction_fixture(account_id: account.id, date: ~D[2026-10-01])

    newer =
      transaction_fixture(
        account_id: account.id,
        subtransactions: [%{amount: -1_000}, %{amount: -250}]
      )

    assert [%Transaction{id: newer_id, subtransactions: [_, _]}, %Transaction{id: older_id}] =
             Ledger.list_transactions(account)

    assert {newer_id, older_id} == {newer.id, older.id}
  end

  test "list_transactions(:all) lists every account's register with payees and categories" do
    payee = payee_fixture()
    category = category_fixture()
    giro = account_fixture()
    cash = account_fixture(kind: :cash)
    older = transaction_fixture(account_id: giro.id, date: ~D[2026-10-01], payee_id: payee.id)
    newer = transaction_fixture(account_id: cash.id, category_id: category.id)
    deleted = transaction_fixture(account_id: cash.id)
    {:ok, _deleted} = Ledger.delete_transaction(deleted)

    assert [listed_newer, listed_older] = Ledger.list_transactions(:all)
    assert {listed_newer.id, listed_older.id} == {newer.id, older.id}
    assert listed_older.payee.name == payee.name
    assert listed_newer.category.category_group.id == category.category_group_id
    assert listed_newer.subtransactions == []
  end

  describe "payee by name" do
    test "takes the regular payee with that lookup key" do
      account = account_fixture()
      payee = payee_fixture(name: "🛒 Rewe")

      assert {:ok, transaction} = Ledger.create_transaction(attrs(account, payee_name: " REWE "))
      assert transaction.payee_id == payee.id
    end

    test "creates a payee that does not exist yet, as entered and trimmed" do
      account = account_fixture()
      category = category_fixture()

      assert {:ok, transaction} =
               Ledger.create_transaction(%{
                 "account_id" => account.id,
                 "date" => "2026-10-09",
                 "amount" => -1_250,
                 "payee_name" => " 🥖 Bäckerei ",
                 "category_id" => category.id
               })

      assert %Payee{name: "🥖 Bäckerei", last_category_id: last} =
               Repo.get!(Payee, transaction.payee_id)

      assert last == category.id
    end

    test "a blank name means no payee" do
      transaction = transaction_fixture(payee_id: payee_fixture().id)

      assert {:ok, %Transaction{payee_id: nil}} =
               Ledger.update_transaction(transaction, %{payee_name: "  "})
    end

    test "is no transfer payee" do
      account = account_fixture()
      account_fixture(name: "Sparkonto")

      assert {:ok, transaction} =
               Ledger.create_transaction(attrs(account, payee_name: "Transfer : Sparkonto"))

      assert %Payee{transfer_account_id: nil} = Repo.get!(Payee, transaction.payee_id)
    end

    test "names the payees of subtransactions too" do
      account = account_fixture()
      rewe = payee_fixture(name: "🛒 Rewe")

      assert {:ok, split} =
               Ledger.create_transaction(
                 attrs(account,
                   subtransactions: [
                     %{amount: -1_000, payee_name: "rewe"},
                     %{amount: -250, payee_name: "Bäcker"},
                     %{amount: 0, payee_name: " "}
                   ]
                 )
               )

      assert [first, second, third] = split.subtransactions
      assert first.payee_id == rewe.id
      assert %Payee{name: "Bäcker"} = Repo.get!(Payee, second.payee_id)
      assert third.payee_id == nil
    end

    test "a refused transaction leaves no new payee behind" do
      assert {:error, _changeset} =
               Ledger.create_transaction(attrs(account_fixture(), payee_name: "Neu", amount: nil))

      assert Ledger.find_payee_by_name("Neu") == {:error, :not_found}
    end
  end

  test "get_transaction!/1 loads what the transaction form shows" do
    giro = account_fixture()
    savings = account_fixture(kind: :savings)

    transfer =
      transaction_fixture(
        account_id: giro.id,
        subtransactions: [
          %{amount: -1_000, payee_id: payee_fixture(name: "Rewe").id},
          %{amount: -250, payee_id: savings.transfer_payee.id}
        ]
      )

    assert %Transaction{subtransactions: [rewe, to_savings], payee: nil} =
             Ledger.get_transaction!(transfer.id)

    assert rewe.payee.name == "Rewe"
    assert to_savings.transfer_transaction.account_id == savings.id

    counterpart = Ledger.get_transaction!(to_savings.transfer_transaction_id)
    assert counterpart.transfer_subtransaction.transaction_id == transfer.id
    assert counterpart.transfer_transaction == nil
  end

  describe "update_transactions/3" do
    setup do
      account = account_fixture()

      %{
        first: transaction_fixture(account_id: account.id, approved: false),
        second: transaction_fixture(account_id: account.id, approved: false),
        reconciled:
          transaction_fixture(account_id: account.id, approved: false, cleared: :reconciled)
      }
    end

    test "changes every transaction", c do
      assert {:ok, [first, second]} =
               Ledger.update_transactions([c.first, c.second], %{approved: true})

      assert first.approved and second.approved
    end

    test "changes none when one is refused", c do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Ledger.update_transactions([c.first, c.reconciled], %{approved: true})

      assert "ist abgeschlossen" in errors_on(changeset).cleared
      refute Repo.get!(Transaction, c.first.id).approved
    end

    test "passes the options on", c do
      assert {:ok, [_first, reconciled]} =
               Ledger.update_transactions([c.first, c.reconciled], %{approved: true},
                 reconciled: :confirmed
               )

      assert reconciled.approved
    end
  end

  describe "references" do
    test "transfer counterparts are the Ledger's, a matched transaction must exist" do
      account = account_fixture()
      other = transaction_fixture()

      assert {:ok, %Transaction{transfer_transaction_id: nil}} =
               Ledger.create_transaction(attrs(account, transfer_transaction_id: other.id))

      assert {:ok, %Transaction{transfer_subtransaction_id: nil}} =
               Ledger.create_transaction(attrs(account, transfer_subtransaction_id: 1))

      assert {:error, changeset} =
               Ledger.create_transaction(
                 attrs(account, source: :bank, matched_transaction_id: -1)
               )

      assert %{matched_transaction_id: ["does not exist"]} = errors_on(changeset)
    end

    test "referenced transactions, payees and categories cannot be deleted" do
      account = account_fixture()
      payee = payee_fixture()
      category = category_fixture()
      existing = transaction_fixture(account_id: account.id)

      transaction_fixture(
        account_id: account.id,
        payee_id: payee.id,
        category_id: category.id,
        source: :bank,
        matched_transaction_id: existing.id
      )

      assert_raise Ecto.ConstraintError, fn -> Repo.delete(existing) end
      assert_raise Ecto.ConstraintError, fn -> Repo.delete(payee) end
      assert_raise Ecto.ConstraintError, fn -> Repo.delete(category) end
    end
  end

  describe "origins" do
    test "an external id is imported once per account and source" do
      account = account_fixture()
      transaction = transaction_fixture(account_id: account.id, source: :file)

      assert {:ok, %TransactionOrigin{account_id: account_id}} =
               Ledger.add_origin(transaction, :file, "FITID-1")

      assert account_id == account.id

      duplicate = transaction_fixture(account_id: account.id, source: :file)
      assert {:error, changeset} = Ledger.add_origin(duplicate, :file, "FITID-1")
      assert %{external_id: ["has already been taken"]} = errors_on(changeset)

      assert {:ok, _} = Ledger.add_origin(duplicate, :bank, "FITID-1")
      assert {:ok, _} = Ledger.add_origin(transaction_fixture(source: :file), :file, "FITID-1")
    end

    test "need an existing transaction" do
      transaction = transaction_fixture()
      Repo.delete!(transaction)

      assert {:error, changeset} = Ledger.add_origin(transaction, :bank, "tx-1")
      assert errors_on(changeset) == %{transaction_id: ["does not exist"]}
    end

    test "go to the transaction's current account" do
      transaction = transaction_fixture()
      savings = account_fixture(kind: :savings)
      {:ok, _} = Ledger.update_transaction(transaction, %{account_id: savings.id})

      assert {:ok, %TransactionOrigin{account_id: account_id}} =
               Ledger.add_origin(transaction, :bank, "tx-1")

      assert account_id == savings.id
    end

    test "requires a known source and an external id" do
      transaction = transaction_fixture()

      assert {:error, changeset} = Ledger.add_origin(transaction, :manual, "")
      assert %{source: ["is invalid"], external_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "a matched transaction keeps the import's origin and is found again" do
      account = account_fixture()
      manual = transaction_fixture(account_id: account.id, memo: "Miete")

      assert Ledger.get_transaction_by_origin(account, :bank, "tx-1") == nil
      {:ok, _} = Ledger.add_origin(manual, :bank, "tx-1")

      assert %Transaction{id: id, source: :manual} =
               Ledger.get_transaction_by_origin(account, :bank, "tx-1")

      assert id == manual.id
    end

    test "move with the transaction to another account" do
      checking = account_fixture()
      savings = account_fixture(kind: :savings)
      transaction = transaction_fixture(account_id: checking.id, source: :bank)
      {:ok, _} = Ledger.add_origin(transaction, :bank, "tx-1")

      {:ok, _} = Ledger.update_transaction(transaction, %{account_id: savings.id})

      assert Ledger.get_transaction_by_origin(checking, :bank, "tx-1") == nil
      assert %Transaction{id: id} = Ledger.get_transaction_by_origin(savings, :bank, "tx-1")
      assert id == transaction.id

      assert {:ok, _} =
               Ledger.add_origin(transaction_fixture(account_id: checking.id), :bank, "tx-1")
    end

    test "cannot move into an account that has the same external id from the same source" do
      checking = account_fixture()
      savings = account_fixture(kind: :savings)
      transaction = transaction_fixture(account_id: checking.id, source: :bank)
      {:ok, _} = Ledger.add_origin(transaction, :bank, "tx-1")
      {:ok, _} = Ledger.add_origin(transaction_fixture(account_id: savings.id), :bank, "tx-1")

      assert {:error, changeset} =
               Ledger.update_transaction(transaction, %{account_id: savings.id})

      assert %{account_id: ["enthält diese Buchung schon aus derselben Quelle"]} =
               errors_on(changeset)

      assert Repo.get!(Transaction, transaction.id).account_id == checking.id
      assert Ledger.get_transaction_by_origin(checking, :bank, "tx-1").id == transaction.id
    end

    test "tell which external ids an account has from a source, deleted transactions included" do
      account = account_fixture()
      kept = transaction_fixture(account_id: account.id, source: :file)
      deleted = transaction_fixture(account_id: account.id, source: :file)
      {:ok, _} = Ledger.add_origin(kept, :file, "A")
      {:ok, _} = Ledger.add_origin(deleted, :file, "B")
      {:ok, _} = Ledger.add_origin(transaction_fixture(account_id: account.id), :bank, "C")
      {:ok, _} = Ledger.add_origin(transaction_fixture(), :file, "D")
      {:ok, _} = Ledger.delete_transaction(deleted)

      assert Ledger.existing_external_ids(account, :file, ~w(A B C D E)) == MapSet.new(~w(A B))
      assert Ledger.existing_external_ids(account, :file, []) == MapSet.new()
    end

    test "go with the transaction row" do
      transaction = transaction_fixture()
      {:ok, _} = Ledger.add_origin(transaction, :ynab, "abc")

      Repo.delete!(transaction)
      assert Repo.aggregate(TransactionOrigin, :count) == 0
    end
  end
end

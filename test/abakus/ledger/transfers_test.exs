defmodule Abakus.Ledger.TransfersTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.{Payee, Subtransaction, Transaction}

  setup do
    %{
      checking: account_fixture(kind: :checking),
      savings: account_fixture(kind: :savings),
      cash: account_fixture(kind: :cash),
      depot: account_fixture(kind: :tracking),
      category: category_fixture()
    }
  end

  defp transfer(from, to, attrs \\ %{}) do
    attrs
    |> Enum.into(%{
      account_id: from.id,
      payee_id: to.transfer_payee.id,
      date: ~D[2026-10-09],
      amount: -1_250
    })
    |> Ledger.create_transaction()
  end

  defp reload(%{id: id}), do: Repo.get!(Transaction, id)

  defp counterpart(%{transfer_transaction_id: id}), do: Repo.get!(Transaction, id)

  defp transfer_payee_account_id(payee_id), do: Repo.get!(Payee, payee_id).transfer_account_id

  # Every transfer side that is not deleted has one counterpart that balances it.
  defp assert_balanced do
    transactions = Repo.all(from t in Transaction, where: is_nil(t.deleted_at))
    by_id = Map.new(transactions, &{&1.id, &1})
    subtransactions = Repo.all(from s in Subtransaction, preload: :transaction)

    sides =
      Enum.filter(transactions, &(&1.transfer_subtransaction_id == nil)) ++
        Enum.filter(subtransactions, &is_nil(&1.transaction.deleted_at))

    for side <- sides, side.payee_id && transfer_payee_account_id(side.payee_id) do
      date = Map.get(side, :date) || side.transaction.date
      account_id = Map.get(side, :account_id) || side.transaction.account_id
      counterpart = Map.fetch!(by_id, side.transfer_transaction_id)

      assert counterpart.amount == -side.amount
      assert counterpart.date == date
      assert counterpart.memo == side.memo
      assert counterpart.account_id == transfer_payee_account_id(side.payee_id)
      assert transfer_payee_account_id(counterpart.payee_id) == account_id

      case side do
        %Transaction{id: id} -> assert counterpart.transfer_transaction_id == id
        %Subtransaction{id: id} -> assert counterpart.transfer_subtransaction_id == id
      end
    end

    for %Transaction{transfer_subtransaction_id: id} = counterpart <- transactions, id do
      assert Enum.find(subtransactions, &(&1.id == id)).transfer_transaction_id == counterpart.id
    end
  end

  describe "creating a transfer" do
    test "creates the counterpart in the other account", c do
      assert {:ok, outflow} = transfer(c.checking, c.savings, memo: "Sparen", flag: :red)
      inflow = counterpart(outflow)

      assert %Transaction{
               amount: 1_250,
               date: ~D[2026-10-09],
               memo: "Sparen",
               category_id: nil,
               cleared: :uncleared,
               approved: true,
               flag: nil,
               source: :manual
             } = inflow

      assert {inflow.account_id, inflow.payee_id, inflow.transfer_transaction_id} ==
               {c.savings.id, c.checking.transfer_payee.id, outflow.id}

      assert Enum.map(Ledger.list_transactions(c.savings), & &1.id) == [inflow.id]
      assert_balanced()
    end

    test "an import's counterpart keeps its source and approval", c do
      {:ok, outflow} = transfer(c.checking, c.savings, source: :file, cleared: :cleared)

      assert %Transaction{source: :file, approved: false, cleared: :uncleared} =
               counterpart(outflow)
    end

    test "the counterpart in a tracking account has no category", c do
      {:ok, outflow} = transfer(c.checking, c.depot, category_id: c.category.id)

      assert %Transaction{category_id: nil, amount: 1_250} = counterpart(outflow)

      assert {:error, changeset} =
               transfer(c.checking, c.depot,
                 category_id: c.category.id,
                 counterpart_category_id: c.category.id
               )

      assert %{counterpart_category_id: ["muss leer sein"]} = errors_on(changeset)
    end

    test "from a tracking account, the budget side's category is given for the counterpart", c do
      assert {:error, changeset} = transfer(c.depot, c.checking)
      assert %{counterpart_category_id: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} = transfer(c.depot, c.checking, counterpart_category_id: -1)
      assert %{counterpart_category_id: ["does not exist"]} = errors_on(changeset)

      {:ok, outflow} = transfer(c.depot, c.checking, counterpart_category_id: c.category.id)
      assert counterpart(outflow).category_id == c.category.id

      assert {:error, changeset} =
               transfer(c.checking, c.savings, counterpart_category_id: c.category.id)

      assert %{counterpart_category_id: ["muss leer sein"]} = errors_on(changeset)
    end

    test "is refused to the own account", c do
      assert {:error, changeset} = transfer(c.checking, c.checking)
      assert %{payee_id: ["darf nicht das eigene Konto sein"]} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.create_transaction(%{
                 account_id: c.checking.id,
                 date: ~D[2026-10-09],
                 amount: -1_250,
                 subtransactions: [
                   %{amount: -1_000},
                   %{amount: -250, payee_id: c.checking.transfer_payee.id}
                 ]
               })

      assert %{subtransactions: [%{}, %{payee_id: ["darf nicht das eigene Konto sein"]}]} =
               errors_on(changeset)

      assert Repo.aggregate(Transaction, :count) == 0
    end

    test "to a closed account is allowed, as imported history has them", c do
      {:ok, savings} = Ledger.update_account(c.savings, %{closed: true})

      assert {:ok, outflow} = transfer(c.checking, savings)
      assert counterpart(outflow).account_id == savings.id
    end
  end

  describe "editing a transfer" do
    test "keeps the counterpart in step, from either side", c do
      {:ok, outflow} = transfer(c.checking, c.savings)

      {:ok, outflow} =
        Ledger.update_transaction(outflow, %{amount: -5_000, date: ~D[2026-10-01], memo: "Rest"})

      assert %Transaction{amount: 5_000, date: ~D[2026-10-01], memo: "Rest"} =
               counterpart(outflow)

      {:ok, _inflow} =
        Ledger.update_transaction(counterpart(outflow), %{amount: 4_000, memo: nil})

      assert %Transaction{amount: -4_000, memo: nil} = reload(outflow)
      assert_balanced()
    end

    test "cleared state, approval and flag belong to each side", c do
      {:ok, outflow} = transfer(c.checking, c.savings)

      {:ok, _} =
        Ledger.update_transaction(counterpart(outflow), %{cleared: :cleared, flag: :green})

      assert %Transaction{cleared: :uncleared, flag: nil} = reload(outflow)
    end

    test "another transfer payee moves the counterpart", c do
      {:ok, outflow} = transfer(c.checking, c.savings)
      inflow = counterpart(outflow)
      {:ok, _} = Ledger.add_origin(inflow, :ynab, "ynab-1")

      {:ok, outflow} = Ledger.update_transaction(outflow, %{payee_id: c.cash.transfer_payee.id})

      assert %Transaction{id: id, account_id: account_id} = counterpart(outflow)
      assert {id, account_id} == {inflow.id, c.cash.id}
      assert Ledger.get_transaction_by_origin(c.cash, :ynab, "ynab-1").id == inflow.id
      assert_balanced()
    end

    test "the counterpart cannot move into an account that has its external id already", c do
      {:ok, outflow} = transfer(c.checking, c.savings)
      {:ok, _} = Ledger.add_origin(counterpart(outflow), :ynab, "ynab-1")
      {:ok, _} = Ledger.add_origin(transaction_fixture(account_id: c.cash.id), :ynab, "ynab-1")

      assert {:error, changeset} =
               Ledger.update_transaction(outflow, %{payee_id: c.cash.transfer_payee.id})

      assert %{
               payee_id: [
                 "führt in ein Konto, das diese Buchung schon aus derselben Quelle enthält"
               ]
             } =
               errors_on(changeset)

      assert counterpart(outflow).account_id == c.savings.id
    end

    test "moving the account gives the counterpart that account's transfer payee", c do
      {:ok, outflow} = transfer(c.checking, c.savings)

      {:ok, outflow} = Ledger.update_transaction(outflow, %{account_id: c.cash.id})

      assert counterpart(outflow).payee_id == c.cash.transfer_payee.id
      assert_balanced()

      assert {:error, changeset} = Ledger.update_transaction(outflow, %{account_id: c.savings.id})
      assert %{payee_id: ["darf nicht das eigene Konto sein"]} = errors_on(changeset)
    end

    test "a regular payee removes the counterpart, a transfer payee brings a new one", c do
      {:ok, outflow} = transfer(c.checking, c.savings)
      inflow = counterpart(outflow)

      {:ok, outflow} = Ledger.update_transaction(outflow, %{payee_id: payee_fixture().id})

      assert outflow.transfer_transaction_id == nil

      assert %Transaction{deleted_at: %DateTime{}, transfer_transaction_id: nil} =
               reload(inflow)

      {:ok, outflow} =
        Ledger.update_transaction(outflow, %{payee_id: c.savings.transfer_payee.id})

      assert %Transaction{id: id, amount: 1_250} = counterpart(outflow)
      assert id != inflow.id
      assert_balanced()
    end

    test "the budget side keeps its category when the tracking side moves on", c do
      {:ok, outflow} = transfer(c.depot, c.checking, counterpart_category_id: c.category.id)

      {:ok, outflow} =
        Ledger.update_transaction(outflow, %{payee_id: c.savings.transfer_payee.id})

      assert %Transaction{account_id: account_id, category_id: category_id} = counterpart(outflow)
      assert {account_id, category_id} == {c.savings.id, c.category.id}
    end

    test "a transfer moving to a tracking account needs the counterpart's category", c do
      {:ok, outflow} = transfer(c.checking, c.savings)

      assert {:error, changeset} = Ledger.update_transaction(outflow, %{account_id: c.depot.id})
      assert %{counterpart_category_id: ["can't be blank"]} = errors_on(changeset)

      {:ok, outflow} =
        Ledger.update_transaction(outflow, %{
          account_id: c.depot.id,
          counterpart_category_id: c.category.id
        })

      assert counterpart(outflow).category_id == c.category.id
    end

    test "turning it into a split removes the counterpart", c do
      {:ok, outflow} = transfer(c.checking, c.savings)
      inflow = counterpart(outflow)

      {:ok, split} =
        Ledger.update_transaction(outflow, %{
          payee_id: nil,
          subtransactions: [%{amount: -1_000}, %{amount: -250}]
        })

      assert split.transfer_transaction_id == nil
      assert reload(inflow).deleted_at
    end
  end

  describe "transfers of subtransactions" do
    setup c do
      {:ok, split} =
        Ledger.create_transaction(%{
          account_id: c.checking.id,
          date: ~D[2026-10-09],
          amount: -1_250,
          subtransactions: [
            %{amount: -1_000, category_id: c.category.id},
            %{amount: -250, payee_id: c.savings.transfer_payee.id, memo: "Sparen"}
          ]
        })

      [groceries, savings] = split.subtransactions
      %{split: split, groceries: groceries, to_savings: savings, inflow: counterpart(savings)}
    end

    test "have a counterpart that points back at the subtransaction", c do
      assert %Transaction{amount: 250, date: ~D[2026-10-09], memo: "Sparen"} = c.inflow
      assert c.inflow.transfer_subtransaction_id == c.to_savings.id
      assert c.inflow.transfer_transaction_id == nil

      assert {c.inflow.account_id, c.inflow.payee_id} ==
               {c.savings.id, c.checking.transfer_payee.id}

      assert c.groceries.transfer_transaction_id == nil
      assert_balanced()
    end

    test "keep the counterpart in step with the split", c do
      {:ok, _} =
        Ledger.update_transaction(c.split, %{
          date: ~D[2026-10-05],
          amount: -1_400,
          subtransactions: [
            %{id: c.groceries.id},
            %{id: c.to_savings.id, amount: -400, memo: nil}
          ]
        })

      assert %Transaction{amount: 400, date: ~D[2026-10-05], memo: nil} = reload(c.inflow)

      {:ok, _} = Ledger.update_transaction(c.split, %{account_id: c.cash.id})
      assert reload(c.inflow).payee_id == c.cash.transfer_payee.id
      assert_balanced()
    end

    test "move, lose or regain the counterpart with the subtransaction's payee", c do
      with_payee = fn payee_id ->
        [%{id: c.groceries.id}, %{id: c.to_savings.id, payee_id: payee_id}]
      end

      {:ok, _} =
        Ledger.update_transaction(c.split, %{
          subtransactions: with_payee.(c.cash.transfer_payee.id)
        })

      assert %Transaction{id: id, account_id: account_id} = reload(c.inflow)
      assert {id, account_id} == {c.inflow.id, c.cash.id}

      {:ok, split} = Ledger.update_transaction(c.split, %{subtransactions: with_payee.(nil)})

      assert %Transaction{deleted_at: %DateTime{}, transfer_subtransaction_id: nil} =
               reload(c.inflow)

      assert Enum.all?(split.subtransactions, &is_nil(&1.transfer_transaction_id))

      {:ok, split} =
        Ledger.update_transaction(c.split, %{
          subtransactions: with_payee.(c.savings.transfer_payee.id)
        })

      assert counterpart(Enum.at(split.subtransactions, 1)).amount == 250
      assert_balanced()
    end

    test "lose the counterpart when the subtransaction goes", c do
      {:ok, _} =
        Ledger.update_transaction(c.split, %{
          subtransactions: [%{id: c.groceries.id}, %{amount: -250}]
        })

      assert reload(c.inflow).deleted_at
      assert Repo.get(Subtransaction, c.to_savings.id) == nil

      {:ok, _} = Ledger.update_transaction(c.split, %{subtransactions: [], category_id: nil})
      assert_balanced()
    end

    test "cannot move their counterpart into an account that has its external id already", c do
      {:ok, _} = Ledger.add_origin(c.inflow, :ynab, "ynab-2")
      {:ok, _} = Ledger.add_origin(transaction_fixture(account_id: c.cash.id), :ynab, "ynab-2")

      assert {:error, changeset} =
               Ledger.update_transaction(c.split, %{
                 subtransactions: [
                   %{id: c.groceries.id},
                   %{id: c.to_savings.id, payee_id: c.cash.transfer_payee.id}
                 ]
               })

      assert %{
               subtransactions: [
                 "führt in ein Konto, das diese Buchung schon aus derselben Quelle enthält"
               ]
             } = errors_on(changeset)

      assert reload(c.inflow).account_id == c.savings.id
    end

    test "their counterpart takes no counterpart category", c do
      assert {:error, changeset} =
               Ledger.update_transaction(c.inflow, %{counterpart_category_id: c.category.id})

      assert %{counterpart_category_id: ["muss leer sein"]} = errors_on(changeset)
    end

    test "change their counterpart in the split; its own fields stay its own", c do
      assert {:error, changeset} =
               Ledger.update_transaction(c.inflow, %{amount: 1, date: ~D[2026-10-01]})

      assert %{
               amount: ["wird in der Aufteilung geändert"],
               date: ["wird in der Aufteilung geändert"]
             } =
               errors_on(changeset)

      assert {:ok, %Transaction{cleared: :cleared, approved: false}} =
               Ledger.update_transaction(c.inflow, %{cleared: :cleared, approved: false})
    end

    test "the counterpart in a budget account takes the category from a tracking split", c do
      {:ok, split} =
        Ledger.create_transaction(%{
          account_id: c.depot.id,
          date: ~D[2026-10-09],
          amount: -500,
          subtransactions: [
            %{amount: -100},
            %{
              amount: -400,
              payee_id: c.checking.transfer_payee.id,
              counterpart_category_id: c.category.id
            }
          ]
        })

      assert counterpart(Enum.at(split.subtransactions, 1)).category_id == c.category.id
    end
  end

  describe "deleting a transfer" do
    test "deletes both sides, from either side", c do
      {:ok, outflow} = transfer(c.checking, c.savings)
      {:ok, _} = Ledger.delete_transaction(outflow)

      assert reload(outflow).deleted_at
      assert counterpart(outflow).deleted_at
      assert Ledger.list_transactions(c.savings) == []

      {:ok, outflow} = transfer(c.checking, c.savings)
      {:ok, _} = Ledger.delete_transaction(counterpart(outflow))

      assert reload(outflow).deleted_at
      assert Ledger.list_transactions(c.checking) == []
    end

    test "deletes the counterparts of a split's subtransactions", c do
      {:ok, split} =
        Ledger.create_transaction(%{
          account_id: c.checking.id,
          date: ~D[2026-10-09],
          amount: -1_250,
          subtransactions: [
            %{amount: -1_000, payee_id: c.cash.transfer_payee.id},
            %{amount: -250, payee_id: c.savings.transfer_payee.id}
          ]
        })

      {:ok, _} = Ledger.delete_transaction(split)

      assert Enum.all?(split.subtransactions, &counterpart(&1).deleted_at)
    end

    test "a subtransaction's counterpart goes only with its split", c do
      {:ok, split} =
        Ledger.create_transaction(%{
          account_id: c.checking.id,
          date: ~D[2026-10-09],
          amount: -1_250,
          subtransactions: [
            %{amount: -1_000},
            %{amount: -250, payee_id: c.savings.transfer_payee.id}
          ]
        })

      inflow = counterpart(Enum.at(split.subtransactions, 1))

      assert {:error, changeset} = Ledger.delete_transaction(inflow)

      assert %{transfer_subtransaction_id: ["wird mit ihrer Aufteilung gelöscht"]} =
               errors_on(changeset)

      refute reload(inflow).deleted_at
      refute reload(split).deleted_at
    end
  end

  describe "the database" do
    test "allows one transfer per counterpart", c do
      {:ok, outflow} = transfer(c.checking, c.savings)
      inflow = counterpart(outflow)

      assert_raise Ecto.ConstraintError, ~r/transactions_transfer_transaction_id_index/, fn ->
        Repo.insert!(%Transaction{
          account_id: c.checking.id,
          date: ~D[2026-10-09],
          amount: -1,
          transfer_transaction_id: inflow.id
        })
      end

      [first, second] =
        Repo.insert!(%Transaction{
          account_id: c.checking.id,
          date: ~D[2026-10-09],
          amount: -2,
          subtransactions: [%Subtransaction{amount: -1}, %Subtransaction{amount: -1}]
        }).subtransactions

      first |> change(transfer_transaction_id: inflow.id) |> Repo.update!()

      assert_raise Ecto.ConstraintError, ~r/subtransactions_transfer_transaction_id_index/, fn ->
        second |> change(transfer_transaction_id: inflow.id) |> Repo.update!()
      end

      assert_raise Ecto.ConstraintError, ~r/transactions_one_transfer_side/, fn ->
        inflow |> change(transfer_subtransaction_id: first.id) |> Repo.update!()
      end
    end
  end

  test "pairs stay balanced through any edits", c do
    accounts = [c.checking, c.savings, c.cash]
    {:ok, _} = transfer(c.checking, c.savings)

    for _ <- 1..60 do
      transaction = Enum.random(Repo.all(Transaction))

      account = Enum.random(accounts)

      payee =
        Enum.random([payee_fixture() | Enum.map(accounts -- [account], & &1.transfer_payee)])

      attrs =
        Enum.random([
          %{amount: Enum.random(-10_000..10_000)},
          %{date: Enum.random([~D[2026-09-30], ~D[2026-10-09]]), memo: Enum.random([nil, "a"])},
          %{account_id: account.id, payee_id: payee.id},
          %{payee_id: payee.id}
        ])

      case Enum.random(1..10) do
        1 -> Ledger.delete_transaction(transaction)
        2 -> transfer(account, Enum.random(accounts -- [account]))
        _ -> Ledger.update_transaction(transaction, attrs)
      end

      assert_balanced()
    end
  end
end

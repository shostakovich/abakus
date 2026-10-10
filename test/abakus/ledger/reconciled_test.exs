defmodule Abakus.Ledger.ReconciledTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.Transaction

  @counterpart "betrifft eine abgeschlossene Gegenbuchung"

  setup do
    %{
      checking: account_fixture(kind: :checking),
      savings: account_fixture(kind: :savings),
      cash: account_fixture(kind: :cash)
    }
  end

  defp reload(%{id: id}), do: Repo.get!(Transaction, id)

  defp counterpart(%{transfer_transaction_id: id}), do: Repo.get!(Transaction, id)

  defp reconcile(transaction) do
    {:ok, _} = Ledger.update_transaction(transaction, %{cleared: :reconciled})
    reload(transaction)
  end

  defp transfer(c) do
    {:ok, outflow} =
      Ledger.create_transaction(%{
        account_id: c.checking.id,
        payee_id: c.savings.transfer_payee.id,
        date: ~D[2026-10-09],
        amount: -1_250,
        memo: "Sparen"
      })

    %{outflow: outflow, inflow: reconcile(counterpart(outflow))}
  end

  defp split(c) do
    {:ok, split} =
      Ledger.create_transaction(%{
        account_id: c.checking.id,
        date: ~D[2026-10-09],
        amount: -1_250,
        subtransactions: [
          %{amount: -1_000},
          %{amount: -250, payee_id: c.savings.transfer_payee.id, memo: "Sparen"}
        ]
      })

    [groceries, to_savings] = split.subtransactions
    inflow = reconcile(counterpart(to_savings))
    %{split: split, groceries: groceries, to_savings: to_savings, inflow: inflow}
  end

  describe "a reconciled transaction" do
    test "changes only when confirmed", c do
      transaction = reconcile(transaction_fixture(account_id: c.checking.id, memo: "Miete"))

      for attrs <- [%{memo: "Pacht"}, %{amount: 1}, %{flag: :red}, %{account_id: c.cash.id}] do
        assert {:error, changeset} = Ledger.update_transaction(transaction, attrs)
        assert %{cleared: ["ist abgeschlossen"]} = errors_on(changeset)
      end

      assert reload(transaction).memo == "Miete"

      assert {:ok, %Transaction{memo: "Pacht", cleared: :reconciled}} =
               Ledger.update_transaction(transaction, %{memo: "Pacht"}, reconciled: :confirmed)
    end

    test "leaves the reconciled state only when confirmed", c do
      transaction = reconcile(transaction_fixture(account_id: c.checking.id))

      assert {:error, changeset} = Ledger.update_transaction(transaction, %{cleared: :cleared})
      assert %{cleared: ["ist abgeschlossen"]} = errors_on(changeset)

      assert {:ok, %Transaction{cleared: :cleared}} =
               Ledger.update_transaction(transaction, %{cleared: :cleared},
                 reconciled: :confirmed
               )
    end

    test "takes an update that changes nothing", c do
      transaction = reconcile(transaction_fixture(account_id: c.checking.id, memo: "Miete"))

      assert {:ok, _} = Ledger.update_transaction(transaction, %{memo: "Miete"})
    end

    test "is deleted only when confirmed", c do
      transaction = reconcile(transaction_fixture(account_id: c.checking.id))

      assert {:error, changeset} = Ledger.delete_transaction(transaction)
      assert %{cleared: ["ist abgeschlossen"]} = errors_on(changeset)
      refute reload(transaction).deleted_at

      assert {:ok, %Transaction{deleted_at: %DateTime{}}} =
               Ledger.delete_transaction(transaction, reconciled: :confirmed)
    end
  end

  describe "a reconciled counterpart" do
    test "keeps amount, date and memo unless confirmed", c do
      %{outflow: outflow, inflow: inflow} = transfer(c)

      for {attrs, field} <- [
            {%{amount: -5_000}, :amount},
            {%{date: ~D[2026-10-01]}, :date},
            {%{memo: "Rest"}, :memo}
          ] do
        assert {:error, changeset} = Ledger.update_transaction(outflow, attrs)
        assert %{^field => [@counterpart]} = errors_on(changeset)
      end

      assert reload(inflow) == inflow
      assert reload(outflow).amount == -1_250

      assert {:ok, _} =
               Ledger.update_transaction(outflow, %{amount: -5_000}, reconciled: :confirmed)

      assert %Transaction{amount: 5_000, cleared: :reconciled} = reload(inflow)
    end

    test "is changed from its own side's fields only", c do
      %{outflow: outflow, inflow: inflow} = transfer(c)

      assert {:ok, _} = Ledger.update_transaction(outflow, %{cleared: :cleared, flag: :red})
      assert reload(inflow) == inflow
    end

    test "is not released unless confirmed", c do
      %{outflow: outflow, inflow: inflow} = transfer(c)

      assert {:error, changeset} =
               Ledger.update_transaction(outflow, %{payee_id: payee_fixture().id})

      assert %{payee_id: [@counterpart]} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.update_transaction(outflow, %{
                 payee_id: nil,
                 subtransactions: [%{amount: -1_000}, %{amount: -250}]
               })

      assert %{subtransactions: [@counterpart]} = errors_on(changeset)
      assert reload(inflow) == inflow
      assert reload(outflow).payee_id == c.savings.transfer_payee.id

      assert {:ok, _} =
               Ledger.update_transaction(outflow, %{payee_id: payee_fixture().id},
                 reconciled: :confirmed
               )

      assert reload(inflow).deleted_at
    end

    test "does not move to another account unless confirmed", c do
      %{outflow: outflow, inflow: inflow} = transfer(c)

      assert {:error, changeset} =
               Ledger.update_transaction(outflow, %{payee_id: c.cash.transfer_payee.id})

      assert %{payee_id: [@counterpart]} = errors_on(changeset)

      assert {:error, changeset} = Ledger.update_transaction(outflow, %{account_id: c.cash.id})
      assert %{account_id: [@counterpart]} = errors_on(changeset)
      assert reload(inflow) == inflow

      assert {:ok, _} =
               Ledger.update_transaction(outflow, %{payee_id: c.cash.transfer_payee.id},
                 reconciled: :confirmed
               )

      assert reload(inflow).account_id == c.cash.id
    end

    test "is not deleted with its other side unless confirmed", c do
      %{outflow: outflow, inflow: inflow} = transfer(c)

      assert {:error, changeset} = Ledger.delete_transaction(outflow)
      assert %{transfer_transaction_id: [@counterpart]} = errors_on(changeset)
      refute reload(outflow).deleted_at
      refute reload(inflow).deleted_at

      assert {:ok, _} = Ledger.delete_transaction(outflow, reconciled: :confirmed)
      assert reload(inflow).deleted_at
    end

    test "locks its other side's amount, date and memo too", c do
      %{outflow: outflow, inflow: inflow} = transfer(c)
      reconcile(outflow)

      {:ok, inflow} =
        Ledger.update_transaction(inflow, %{cleared: :cleared}, reconciled: :confirmed)

      assert {:error, changeset} = Ledger.update_transaction(inflow, %{amount: 1})
      assert %{amount: [@counterpart]} = errors_on(changeset)
      assert reload(outflow).amount == -1_250
    end
  end

  describe "a reconciled counterpart of a subtransaction" do
    test "keeps amount, date and memo unless confirmed", c do
      %{split: split, groceries: groceries, to_savings: to_savings, inflow: inflow} = split(c)

      subtransactions = fn attrs ->
        [%{id: groceries.id, amount: -1_000}, Map.put(attrs, :id, to_savings.id)]
      end

      assert {:error, changeset} =
               Ledger.update_transaction(split, %{
                 amount: -1_300,
                 subtransactions: subtransactions.(%{amount: -300})
               })

      assert %{subtransactions: [@counterpart]} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.update_transaction(split, %{
                 subtransactions: subtransactions.(%{memo: "Rest"})
               })

      assert %{subtransactions: [@counterpart]} = errors_on(changeset)

      assert {:error, changeset} = Ledger.update_transaction(split, %{date: ~D[2026-10-01]})
      assert %{date: [@counterpart]} = errors_on(changeset)
      assert reload(inflow) == inflow

      assert {:ok, _} =
               Ledger.update_transaction(split, %{date: ~D[2026-10-01]}, reconciled: :confirmed)

      assert reload(inflow).date == ~D[2026-10-01]
    end

    test "is not released or moved unless confirmed", c do
      %{split: split, groceries: groceries, to_savings: to_savings, inflow: inflow} = split(c)

      for subtransactions <- [
            [%{id: groceries.id}, %{amount: -250}],
            [%{id: groceries.id}, %{id: to_savings.id, payee_id: nil}],
            [%{id: groceries.id}, %{id: to_savings.id, payee_id: c.cash.transfer_payee.id}]
          ] do
        assert {:error, changeset} =
                 Ledger.update_transaction(split, %{subtransactions: subtransactions})

        assert %{subtransactions: [@counterpart]} = errors_on(changeset)
      end

      assert reload(inflow) == inflow

      assert {:ok, _} =
               Ledger.update_transaction(
                 split,
                 %{subtransactions: [%{id: groceries.id}, %{amount: -250}]},
                 reconciled: :confirmed
               )

      assert reload(inflow).deleted_at
    end

    test "is not deleted with its split unless confirmed", c do
      %{split: split, inflow: inflow} = split(c)

      assert {:error, changeset} = Ledger.delete_transaction(split)
      assert %{subtransactions: [@counterpart]} = errors_on(changeset)
      refute reload(inflow).deleted_at

      assert {:ok, _} = Ledger.delete_transaction(split, reconciled: :confirmed)
      assert reload(inflow).deleted_at
    end
  end

  test "accepting a match that changes a reconciled counterpart needs confirmation", c do
    %{outflow: outflow, inflow: inflow} = transfer(c)

    {:ok, proposal} =
      Ledger.create_transaction(%{
        account_id: c.checking.id,
        date: ~D[2026-10-07],
        amount: -1_250,
        source: :bank,
        matched_transaction_id: outflow.id
      })

    assert {:error, changeset} = Ledger.accept_match(proposal)
    assert %{date: [@counterpart]} = errors_on(changeset)
    assert reload(inflow) == inflow

    assert {:ok, _} = Ledger.accept_match(proposal, reconciled: :confirmed)
    assert reload(inflow).date == ~D[2026-10-07]
  end
end

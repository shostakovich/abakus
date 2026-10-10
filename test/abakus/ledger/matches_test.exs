defmodule Abakus.Ledger.MatchesTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.{Payee, Transaction, TransactionOrigin}

  setup do
    account = account_fixture()
    category = category_fixture()

    manual =
      transaction_fixture(
        account_id: account.id,
        date: ~D[2026-10-03],
        amount: -4_875,
        category_id: category.id,
        memo: "Drogerie"
      )

    %{account: account, category: category, manual: manual}
  end

  defp propose(c, attrs \\ %{}) do
    {external_id, attrs} = attrs |> Map.new() |> Map.pop(:external_id, "tx-7")

    {:ok, proposal} =
      attrs
      |> Enum.into(%{
        account_id: c.account.id,
        date: ~D[2026-10-07],
        amount: -4_875,
        memo: "DROGERIE SAUBER",
        cleared: :cleared,
        source: :bank,
        matched_transaction_id: c.manual.id
      })
      |> Ledger.create_transaction()

    {:ok, _} = Ledger.add_origin(proposal, :bank, external_id)
    proposal
  end

  test "a proposal counts nowhere until it is decided", c do
    proposal = propose(c)

    assert Enum.map(Ledger.list_transactions(c.account), & &1.id) == [c.manual.id]

    assert [%Transaction{id: id, matched_transaction: matched}] =
             Ledger.list_match_proposals(c.account)

    assert {id, matched.id} == {proposal.id, c.manual.id}
    assert Repo.aggregate(Ledger.in_register(), :count) == 1
  end

  test "one proposal per existing transaction, in its account", c do
    propose(c)

    attrs = %{account_id: c.account.id, date: ~D[2026-10-07], amount: -4_875, source: :file}

    assert {:error, changeset} =
             Ledger.create_transaction(Map.put(attrs, :matched_transaction_id, c.manual.id))

    assert %{matched_transaction_id: ["has already been taken"]} = errors_on(changeset)

    other = transaction_fixture(amount: -4_875)

    assert {:error, changeset} =
             Ledger.create_transaction(Map.put(attrs, :matched_transaction_id, other.id))

    assert %{matched_transaction_id: ["muss im selben Konto sein"]} = errors_on(changeset)
  end

  test "a proposal needs the same amount and an open transaction in the register", c do
    attrs = %{account_id: c.account.id, date: ~D[2026-10-07], amount: -4_875, source: :bank}

    assert {:error, changeset} =
             Ledger.create_transaction(
               %{attrs | amount: -999}
               |> Map.put(:matched_transaction_id, c.manual.id)
             )

    assert %{matched_transaction_id: ["muss denselben Betrag haben"]} = errors_on(changeset)

    proposal = propose(c)

    assert {:error, changeset} =
             Ledger.create_transaction(Map.put(attrs, :matched_transaction_id, proposal.id))

    assert %{matched_transaction_id: ["ist selbst ein Zuordnungsvorschlag"]} =
             errors_on(changeset)

    reconciled =
      transaction_fixture(account_id: c.account.id, amount: -4_875, cleared: :reconciled)

    assert {:error, changeset} =
             Ledger.create_transaction(Map.put(attrs, :matched_transaction_id, reconciled.id))

    assert %{matched_transaction_id: ["ist abgeschlossen"]} = errors_on(changeset)
  end

  test "deleting a proposal frees its transaction for the next one", c do
    proposal = propose(c)

    {:ok, _} = Ledger.delete_transaction(proposal)

    assert %Transaction{matched_transaction_id: nil, deleted_at: %DateTime{}} =
             Repo.get!(Transaction, proposal.id)

    assert {:ok, _} =
             Ledger.create_transaction(%{
               account_id: c.account.id,
               date: ~D[2026-10-07],
               amount: -4_875,
               source: :bank,
               matched_transaction_id: c.manual.id
             })
  end

  test "only imports from a file or the bank propose a match", c do
    attrs = %{account_id: c.account.id, date: ~D[2026-10-07], amount: -4_875}

    for source <- [:manual, :ynab, :api] do
      assert {:error, changeset} =
               Ledger.create_transaction(
                 Map.merge(attrs, %{source: source, matched_transaction_id: c.manual.id})
               )

      assert %{matched_transaction_id: ["ist nur bei Importen aus Datei oder Bank möglich"]} =
               errors_on(changeset)
    end

    assert {:ok, _} =
             Ledger.create_transaction(
               Map.merge(attrs, %{source: :file, matched_transaction_id: c.manual.id})
             )
  end

  test "a proposal leaves its payee's last category alone", c do
    payee = payee_fixture()
    remembered = category_fixture()
    {:ok, _} = Ledger.update_payee(payee, %{last_category_id: remembered.id})

    proposal = propose(c, payee_id: payee.id, category_id: category_fixture().id)
    assert Repo.get!(Payee, payee.id).last_category_id == remembered.id

    {:ok, _} = Ledger.reject_match(proposal)
    assert Repo.get!(Payee, payee.id).last_category_id == remembered.id
  end

  test "while a proposal is open, account and amount of both sides are fixed", c do
    proposal = propose(c)
    other = account_fixture(kind: :savings)
    locked = "kann bei einem offenen Zuordnungsvorschlag nicht geändert werden"

    for transaction <- [proposal, c.manual] do
      assert {:error, changeset} =
               Ledger.update_transaction(transaction, %{account_id: other.id, amount: -1})

      assert %{account_id: [^locked], amount: [^locked]} = errors_on(changeset)
    end

    assert {:ok, _} = Ledger.update_transaction(c.manual, %{memo: "Drogerie Sauber"})
    assert {:ok, %Transaction{account_id: account_id}} = Ledger.accept_match(proposal)
    assert account_id == c.account.id
  end

  test "a proposal can still be rejected after a refused move", c do
    proposal = propose(c)
    other = account_fixture(kind: :savings)

    assert {:error, _} = Ledger.update_transaction(proposal, %{account_id: other.id})
    assert {:ok, %Transaction{account_id: account_id}} = Ledger.reject_match(proposal)
    assert account_id == c.account.id
  end

  test "a counterpart with an open proposal keeps its account and amount", c do
    savings = account_fixture(kind: :savings)
    cash = account_fixture(kind: :cash)

    {:ok, outflow} =
      Ledger.create_transaction(%{
        account_id: c.account.id,
        date: ~D[2026-10-01],
        amount: -10_000,
        payee_id: savings.transfer_payee.id
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        account_id: savings.id,
        date: ~D[2026-10-02],
        amount: 10_000,
        source: :bank,
        matched_transaction_id: outflow.transfer_transaction_id
      })

    assert {:error, changeset} = Ledger.update_transaction(outflow, %{amount: -1})

    assert %{
             amount: [
               "kann nicht geändert werden, solange die Gegenbuchung einen offenen Zuordnungsvorschlag hat"
             ]
           } =
             errors_on(changeset)

    assert {:error, changeset} =
             Ledger.update_transaction(outflow, %{payee_id: cash.transfer_payee.id})

    assert %{payee_id: [_]} = errors_on(changeset)
    assert Repo.get!(Transaction, outflow.transfer_transaction_id).account_id == savings.id
  end

  test "accepting re-checks the proposal and its transaction", c do
    proposal = propose(c)

    {:ok, _} = Ledger.update_transaction(c.manual, %{cleared: :reconciled})

    assert {:error, changeset} = Ledger.accept_match(proposal)
    assert %{matched_transaction_id: ["ist abgeschlossen"]} = errors_on(changeset)

    {:ok, _} = Ledger.update_transaction(c.manual, %{cleared: :cleared}, reconciled: :confirmed)
    other = account_fixture(kind: :savings)
    {:ok, _} = Ledger.add_origin(transaction_fixture(account_id: other.id), :bank, "tx-7")

    # Rows changed behind the Ledger's back, e.g. by hand in the database.
    Repo.update_all(from(t in Transaction, where: t.id == ^proposal.id),
      set: [account_id: other.id]
    )

    assert {:error, changeset} = Ledger.accept_match(proposal)
    assert %{matched_transaction_id: ["muss im selben Konto sein"]} = errors_on(changeset)

    Repo.update_all(from(t in Transaction, where: t.id == ^proposal.id),
      set: [account_id: c.account.id, amount: -1]
    )

    assert {:error, changeset} = Ledger.accept_match(proposal)
    assert %{matched_transaction_id: ["muss denselben Betrag haben"]} = errors_on(changeset)
    assert Repo.get(Transaction, proposal.id)
    assert Ledger.get_transaction_by_origin(c.account, :bank, "tx-7").id == proposal.id
  end

  test "accepting into a split takes the date for the split and its counterparts", c do
    savings = account_fixture(kind: :savings)

    {:ok, split} =
      Ledger.create_transaction(%{
        account_id: c.account.id,
        date: ~D[2026-10-01],
        amount: -500,
        subtransactions: [
          %{amount: -100, category_id: c.category.id},
          %{amount: -400, payee_id: savings.transfer_payee.id}
        ]
      })

    proposal = propose(c, amount: -500, matched_transaction_id: split.id)

    assert {:ok, %Transaction{date: ~D[2026-10-07], memo: "DROGERIE SAUBER", category_id: nil}} =
             Ledger.accept_match(proposal)

    counterpart_id = Enum.at(split.subtransactions, 1).transfer_transaction_id
    assert Repo.get!(Transaction, counterpart_id).date == ~D[2026-10-07]
  end

  test "accepting into a split's counterpart takes only the cleared state", c do
    savings = account_fixture(kind: :savings)

    {:ok, split} =
      Ledger.create_transaction(%{
        account_id: savings.id,
        date: ~D[2026-10-01],
        amount: -500,
        subtransactions: [%{amount: -100}, %{amount: -400, payee_id: c.account.transfer_payee.id}]
      })

    inflow_id = Enum.at(split.subtransactions, 1).transfer_transaction_id
    proposal = propose(c, amount: 400, matched_transaction_id: inflow_id)

    assert {:ok, %Transaction{date: ~D[2026-10-01], memo: nil, cleared: :cleared, approved: true}} =
             Ledger.accept_match(proposal)
  end

  test "a proposal is no transfer and no split", c do
    savings = account_fixture(kind: :savings)
    attrs = %{account_id: c.account.id, date: ~D[2026-10-07], amount: -4_875, source: :bank}

    attrs =
      Map.put(attrs, :matched_transaction_id, transaction_fixture(account_id: c.account.id).id)

    assert {:error, changeset} =
             Ledger.create_transaction(Map.put(attrs, :payee_id, savings.transfer_payee.id))

    assert %{payee_id: ["darf bei einem Zuordnungsvorschlag keine Umbuchung sein"]} =
             errors_on(changeset)

    assert {:error, changeset} =
             Ledger.create_transaction(
               Map.put(attrs, :subtransactions, [%{amount: -4_000}, %{amount: -875}])
             )

    assert %{subtransactions: ["muss bei einem Zuordnungsvorschlag leer sein"]} =
             errors_on(changeset)
  end

  test "the proposal is set once", c do
    transaction = transaction_fixture(account_id: c.account.id)

    assert {:ok, %Transaction{matched_transaction_id: nil}} =
             Ledger.update_transaction(transaction, %{matched_transaction_id: c.manual.id})
  end

  test "accepting merges the import into the existing transaction", c do
    proposal = propose(c)

    assert {:ok, merged} = Ledger.accept_match(proposal)

    assert %Transaction{
             date: ~D[2026-10-07],
             cleared: :cleared,
             approved: true,
             memo: "Drogerie",
             amount: -4_875,
             source: :manual
           } = merged

    assert {merged.id, merged.category_id} == {c.manual.id, c.category.id}
    assert Repo.get(Transaction, proposal.id) == nil
    assert Ledger.get_transaction_by_origin(c.account, :bank, "tx-7").id == c.manual.id
    assert Repo.aggregate(TransactionOrigin, :count) == 1
    assert Ledger.list_match_proposals(c.account) == []
  end

  test "accepting takes the import's category and memo where the manual entry has none", c do
    blank = transaction_fixture(account_id: c.account.id, date: ~D[2026-10-02], amount: -999)
    imported = category_fixture()

    proposal =
      propose(c, amount: -999, category_id: imported.id, matched_transaction_id: blank.id)

    assert {:ok, %Transaction{memo: "DROGERIE SAUBER", category_id: category_id}} =
             Ledger.accept_match(proposal)

    assert category_id == imported.id
  end

  test "accepting keeps a manual category and memo over the import's", c do
    proposal = propose(c, category_id: category_fixture().id)

    assert {:ok, %Transaction{memo: "Drogerie", category_id: category_id}} =
             Ledger.accept_match(proposal)

    assert category_id == c.category.id
  end

  test "accepting a match for a transfer moves its counterpart's date along", c do
    savings = account_fixture(kind: :savings)

    {:ok, outflow} =
      Ledger.create_transaction(%{
        account_id: c.account.id,
        date: ~D[2026-10-01],
        amount: -10_000,
        payee_id: savings.transfer_payee.id
      })

    proposal = propose(c, amount: -10_000, matched_transaction_id: outflow.id)

    {:ok, _} = Ledger.accept_match(proposal)

    assert Repo.get!(Transaction, outflow.transfer_transaction_id).date == ~D[2026-10-07]
  end

  test "rejecting separates the import and approves it as a transaction of its own", c do
    proposal = propose(c)
    refute proposal.approved

    assert {:ok, %Transaction{matched_transaction_id: nil, approved: true}} =
             Ledger.reject_match(proposal)

    assert Enum.map(Ledger.list_transactions(c.account), & &1.id) == [proposal.id, c.manual.id]
    assert Ledger.list_match_proposals(c.account) == []
  end

  test "deleting the existing transaction turns its proposal into an ordinary import", c do
    proposal = propose(c)

    {:ok, _} = Ledger.delete_transaction(c.manual)

    assert Repo.get!(Transaction, proposal.id).matched_transaction_id == nil
    assert Enum.map(Ledger.list_transactions(c.account), & &1.id) == [proposal.id]
  end

  test "only pending proposals can be decided", c do
    assert Ledger.accept_match(c.manual) == {:error, :not_a_proposal}
    assert Ledger.reject_match(c.manual) == {:error, :not_a_proposal}

    proposal = propose(c)
    {:ok, _} = Ledger.reject_match(proposal)
    assert Ledger.accept_match(proposal) == {:error, :not_a_proposal}
  end

  describe "find_matches/3" do
    defp import_row(date, amount \\ -4_875), do: %{date: date, amount: amount}

    test "proposes the closest date within 10 days, on a tie the older transaction", c do
      before = transaction_fixture(account_id: c.account.id, date: ~D[2026-10-01], amount: -4_875)
      later = transaction_fixture(account_id: c.account.id, date: ~D[2026-10-13], amount: -4_875)

      find =
        &ids(Ledger.find_matches(c.account, :file, Enum.map(&1, fn date -> import_row(date) end)))

      assert find.([~D[2026-10-04]]) == [c.manual.id]
      assert find.([~D[2026-10-02]]) == [before.id]
      # Once 10-03 is taken, 10-01 and 10-13 are both six days from 10-07.
      assert find.([~D[2026-10-07], ~D[2026-10-03]]) == [before.id, c.manual.id]
      assert find.([~D[2026-10-23]]) == [later.id]
      assert find.([~D[2026-10-24]]) == [nil]
    end

    test "proposes the closest pair, whichever import comes first", c do
      at = transaction_fixture(account_id: c.account.id, date: ~D[2026-10-05], amount: -450)
      early = import_row(~D[2026-10-01], -450)
      same_day = import_row(~D[2026-10-05], -450)

      assert ids(Ledger.find_matches(c.account, :file, [early, same_day])) == [nil, at.id]
      assert ids(Ledger.find_matches(c.account, :file, [same_day, early])) == [at.id, nil]
    end

    test "matches a transaction once, with the same amount in the same account", c do
      other = account_fixture()
      transaction_fixture(account_id: other.id, date: ~D[2026-10-03], amount: -4_875)

      assert ids(
               Ledger.find_matches(c.account, :file, [
                 import_row(~D[2026-10-04]),
                 import_row(~D[2026-10-03]),
                 import_row(~D[2026-10-03], -4_876)
               ])
             ) == [nil, c.manual.id, nil]
    end

    test "leaves out reconciled, deleted, already proposed and already imported transactions",
         c do
      at = ~D[2026-10-03]
      reconciled = transaction_fixture(account_id: c.account.id, date: at, cleared: :reconciled)
      deleted = transaction_fixture(account_id: c.account.id, date: at)
      {:ok, _} = Ledger.delete_transaction(deleted)
      imported = transaction_fixture(account_id: c.account.id, date: at, source: :file)
      {:ok, _} = Ledger.add_origin(imported, :file, "MM-1")
      from_ynab = transaction_fixture(account_id: c.account.id, date: at, source: :ynab)
      {:ok, _} = Ledger.add_origin(from_ynab, :ynab, "ynab-1")
      propose(c)

      rows = [import_row(at, -1_250), import_row(at, -1_250), import_row(at)]

      assert ids(Ledger.find_matches(c.account, :file, rows)) == [from_ynab.id, nil, nil]
      assert ids(Ledger.find_matches(c.account, :bank, rows)) == [imported.id, from_ynab.id, nil]
      refute reconciled.id in ids(Ledger.find_matches(c.account, :bank, rows))
    end

    test "looks up more amounts than SQLite takes variables", c do
      rows = Enum.map(1..40_000, &import_row(~D[2026-10-03], -&1))

      assert c.manual.id in ids(Ledger.find_matches(c.account, :file, rows))
    end

    test "finds nothing without imports", c do
      assert Ledger.find_matches(c.account, :file, []) == []
    end
  end

  defp ids(transactions), do: Enum.map(transactions, &(&1 && &1.id))

  test "the newest reconciled transaction's date, of the register", c do
    assert Ledger.last_reconciled_date(c.account) == nil

    transaction_fixture(account_id: c.account.id, date: ~D[2026-09-15], cleared: :reconciled)

    deleted =
      transaction_fixture(account_id: c.account.id, date: ~D[2026-09-30], cleared: :reconciled)

    {:ok, _} = Ledger.delete_transaction(deleted, reconciled: :confirmed)
    transaction_fixture(date: ~D[2026-10-01], cleared: :reconciled)

    assert Ledger.last_reconciled_date(c.account) == ~D[2026-09-15]
  end

  test "proposals wait for approval in the balances but add nothing to them", c do
    propose(c)

    assert Ledger.balances()[c.account.id] == %{
             balance: -4_875,
             cleared: 0,
             uncleared: -4_875,
             unapproved: 1
           }
  end

  test "lists every account's proposals with what they would merge into", c do
    proposal = propose(c)
    other = account_fixture()
    elsewhere = transaction_fixture(account_id: other.id, amount: -100)
    other_proposal = propose(%{c | account: other, manual: elsewhere}, amount: -100)

    assert [%{id: first, matched_transaction: %Transaction{payee: nil}}, %{id: second}] =
             Ledger.list_match_proposals(:all)

    assert {first, second} == {other_proposal.id, proposal.id}
  end

  describe "accept_matches/2" do
    test "accepts all or none", c do
      proposal = propose(c)
      blank = transaction_fixture(account_id: c.account.id, date: ~D[2026-10-02], amount: -999)
      other = propose(c, amount: -999, matched_transaction_id: blank.id, external_id: "tx-8")

      assert {:ok, [_, _]} = Ledger.accept_matches([proposal, other])
      assert Ledger.list_match_proposals(c.account) == []
      assert Repo.get!(Transaction, blank.id).approved
    end

    test "the first refusal stops", c do
      proposal = propose(c)
      blank = transaction_fixture(account_id: c.account.id, date: ~D[2026-10-02], amount: -999)
      other = propose(c, amount: -999, matched_transaction_id: blank.id, external_id: "tx-8")

      Repo.update_all(from(t in Transaction, where: t.id == ^blank.id),
        set: [cleared: :reconciled]
      )

      assert {:error, changeset} = Ledger.accept_matches([proposal, other])
      assert %{matched_transaction_id: ["ist abgeschlossen"]} = errors_on(changeset)
      assert length(Ledger.list_match_proposals(c.account)) == 2
    end
  end
end

defmodule Abakus.Ledger.PayeesTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.UsersFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.{Payee, PayeeRenameCondition, Payees, Scheduled, Transaction}
  alias Abakus.Sync.Message

  describe "create_payee/2" do
    test "stores the name as entered with its lookup key" do
      category = category_fixture()

      assert {:ok, payee} =
               Ledger.create_payee(budget_scope(), %{
                 name: "🛒 REWE",
                 last_category_id: category.id
               })

      assert %Payee{name: "🛒 REWE", lookup_key: "rewe", transfer_account_id: nil} = payee
      assert payee.last_category_id == category.id
    end

    test "requires a name" do
      assert {:error, changeset} = Ledger.create_payee(budget_scope(), %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "regular payees are unique by lookup key" do
      payee_fixture(name: "Rewe")

      assert {:error, changeset} = Ledger.create_payee(budget_scope(), %{name: "🛒 REWE"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.update_payee(budget_scope(), payee_fixture(name: "Aldi"), %{name: "REWE"})

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "the same name in decomposed form or with ss is the same payee" do
      payee_fixture(name: "B\u00E4ckerei Stra\u00DFe")

      assert {:error, _} = Ledger.create_payee(budget_scope(), %{name: "Ba\u0308ckerei STRASSE"})
      assert {:ok, _} = Ledger.find_payee_by_name(budget_scope(), "ba\u0308ckerei strasse")
    end

    test "a regular payee may share its lookup key with a transfer payee" do
      account = account_fixture(name: "Girokonto")

      assert {:ok, payee} = Ledger.create_payee(budget_scope(), %{name: "transfer : GIROKONTO"})
      assert payee.lookup_key == account.transfer_payee.lookup_key
    end

    test "an account has only one transfer payee" do
      account = account_fixture()

      assert {:error, changeset} =
               %Payee{user_id: account.user_id}
               |> Payee.transfer_changeset(account)
               |> Repo.insert()

      assert %{transfer_account_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "the last category must exist" do
      assert {:error, changeset} =
               Ledger.create_payee(budget_scope(), %{
                 name: "Aldi",
                 last_category_id: Ecto.UUID.generate()
               })

      assert %{last_category_id: ["does not exist"]} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.update_payee(budget_scope(), payee_fixture(), %{
                 last_category_id: Ecto.UUID.generate()
               })

      assert %{last_category_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "update_payee/3" do
    test "renames a regular payee and its lookup key" do
      payee = payee_fixture(name: "Rewe")

      assert {:ok, %Payee{name: "🛒 Rewe Markt", lookup_key: "rewe markt"}} =
               Ledger.update_payee(budget_scope(), payee, %{name: "🛒 Rewe Markt"})
    end

    test "a transfer payee keeps the account's name" do
      account = account_fixture(name: "Girokonto")

      assert {:error, changeset} =
               Ledger.update_payee(budget_scope(), account.transfer_payee, %{name: "Anders"})

      assert %{name: ["folgt dem Kontonamen"]} = errors_on(changeset)
    end
  end

  describe "find_payee_by_name/2" do
    test "ignores emoji and case" do
      payee = payee_fixture(name: "🛒 Rewe")

      assert {:ok, %Payee{id: id}} = Ledger.find_payee_by_name(budget_scope(), "REWE")
      assert id == payee.id
      assert {:ok, %Payee{id: ^id}} = Ledger.find_payee_by_name(budget_scope(), "🛍️rewe ")
    end

    test "finds transfer payees" do
      account = account_fixture(name: "💳 Girokonto")
      id = account.transfer_payee.id

      assert {:ok, %Payee{id: ^id}} =
               Ledger.find_payee_by_name(budget_scope(), "Transfer : Girokonto")
    end

    test "prefers the regular payee over a transfer payee of the same name" do
      account_fixture(name: "Girokonto")
      payee = payee_fixture(name: "Transfer : Girokonto")

      assert {:ok, found} = Ledger.find_payee_by_name(budget_scope(), "transfer : girokonto")
      assert found.id == payee.id
    end

    test "is ambiguous between transfer payees of accounts with the same name" do
      account_fixture(name: "Tagesgeld")
      account_fixture(name: "💰 Tagesgeld")

      assert Ledger.find_payee_by_name(budget_scope(), "Transfer : Tagesgeld") ==
               {:error, :ambiguous}
    end

    test "reports unknown names" do
      assert Ledger.find_payee_by_name(budget_scope(), "Niemand") == {:error, :not_found}
    end
  end

  test "list_payees/0 lists the regular payees by name" do
    account_fixture(name: "Girokonto")
    payee_fixture(name: "🛒 Rewe")
    payee_fixture(name: "Aldi")

    assert ["Aldi", "🛒 Rewe"] = Enum.map(Ledger.list_payees(budget_scope()), & &1.name)
  end

  describe "merge_duplicate_payees/2" do
    test "merges payees with one lookup key into the oldest, which takes over what pointed at the others" do
      category = category_fixture()
      oldest = payee_fixture(name: "Bäckerei Korn")

      newer =
        Repo.insert!(%Payee{
          user_id: oldest.user_id,
          name: "BÄCKEREI KORN",
          lookup_key: oldest.lookup_key,
          last_category_id: category.id
        })

      booked = transaction_fixture(payee_id: newer.id)

      condition =
        Repo.insert!(%PayeeRenameCondition{
          user_id: oldest.user_id,
          payee_id: newer.id,
          operator: :contains,
          text: "KORN"
        })

      assert :ok = Ledger.merge_duplicate_payees(budget_scope(), [newer.id])

      assert Repo.reload(booked).payee_id == oldest.id
      assert Repo.reload(condition).payee_id == oldest.id
      assert %Payee{deleted_at: %DateTime{}, successor_id: successor_id} = Repo.reload(newer)
      assert successor_id == oldest.id
      assert Repo.reload(oldest).last_category_id == category.id
      assert [%Payee{id: id}] = Ledger.list_payees(budget_scope())
      assert id == oldest.id
    end

    test "leaves a payee alone whose lookup key is its own" do
      payee = payee_fixture(name: "Aldi")

      assert :ok = Ledger.merge_duplicate_payees(budget_scope(), [payee.id])
      assert Repo.reload(payee).deleted_at == nil
    end
  end

  describe "managing payees" do
    setup do
      %{giro: account_fixture(name: "Girokonto")}
    end

    defp book(c, payee, times \\ 1) do
      for _ <- 1..times//1,
          do: transaction_fixture(account_id: c.giro.id, payee_id: payee.id)
    end

    defp rules(payee) do
      Repo.all(
        from r in PayeeRenameCondition,
          where: r.payee_id == ^payee.id and is_nil(r.deleted_at),
          order_by: r.position,
          select: {r.position, r.operator, r.text}
      )
    end

    defp rule!(payee, operator, text, position \\ 0) do
      Repo.insert!(%PayeeRenameCondition{
        user_id: payee.user_id,
        payee_id: payee.id,
        operator: operator,
        text: text,
        position: position
      })
    end

    defp overview, do: Map.new(Payees.list(budget_scope()), &{&1.payee.name, &1})

    defp count_of(payee),
      do:
        Repo.aggregate(
          from(t in Transaction, where: t.payee_id == ^payee.id and is_nil(t.deleted_at)),
          :count
        )

    defp messages_after(cursor, table) do
      Repo.all(
        from m in Message,
          where: m.id > ^cursor and m.table == ^table,
          select: {m.row_id, m.column, m.value}
      )
    end

    test "list/1 shows the regular payees, hidden ones too, with their rules and transactions",
         c do
      rewe = payee_fixture(name: "Rewe")
      aldi = payee_fixture(name: "Aldi", hidden: true)
      rule!(rewe, :is, "REWE Markt", 1)
      rule!(rewe, :starts_with, "REWE", 0)
      book(c, rewe, 2)
      deleted = hd(book(c, rewe))
      {:ok, _deleted} = Ledger.delete_transaction(budget_scope(), deleted)

      {:ok, _split} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.giro.id,
          date: ~D[2026-10-10],
          amount: -300,
          payee_id: rewe.id,
          subtransactions: [
            %{amount: -100, payee_id: rewe.id},
            %{amount: -200, payee_id: aldi.id}
          ]
        })

      {:ok, _scheduled} =
        Scheduled.create(budget_scope(), %{
          account_id: c.giro.id,
          next_date: ~D[2026-12-01],
          repeat_unit: :month,
          repeat_every: 1,
          payee_id: aldi.id,
          amount: -500
        })

      assert ["Aldi", "Rewe"] = Enum.map(Payees.list(budget_scope()), & &1.payee.name)
      assert %{"Aldi" => listed_aldi, "Rewe" => listed_rewe} = overview()
      assert listed_aldi.payee.hidden
      assert listed_aldi.transaction_count == 2
      assert listed_aldi.rename_conditions == []
      assert listed_rewe.transaction_count == 3

      assert [{:starts_with, "REWE"}, {:is, "REWE Markt"}] =
               Enum.map(listed_rewe.rename_conditions, &{&1.operator, &1.text})
    end

    test "list/1 says which payees scheduled transactions use", c do
      rewe = payee_fixture(name: "Rewe")
      aldi = payee_fixture(name: "Aldi")
      book(c, aldi)

      {:ok, _scheduled} =
        Scheduled.create(budget_scope(), %{
          account_id: c.giro.id,
          next_date: ~D[2026-12-01],
          repeat_unit: :month,
          repeat_every: 1,
          payee_id: rewe.id,
          amount: -500
        })

      assert %{"Rewe" => %{scheduled: true}, "Aldi" => %{scheduled: false}} = overview()
    end

    test "renaming to an existing name merges into that payee", c do
      rewe = payee_fixture(name: "Rewe")
      markt = payee_fixture(name: "REWE Markt GmbH")
      book(c, rewe, 3)
      book(c, markt, 2)

      assert {:ok, %Payee{id: id, name: "Rewe"}} = Payees.rename(budget_scope(), markt, "rewe")
      assert id == rewe.id
      assert %{"Rewe" => %{transaction_count: 5}} = overview()
      assert map_size(overview()) == 1
      assert rules(rewe) == [{0, :is, "REWE Markt GmbH"}]
      assert %Payee{deleted_at: %DateTime{}, successor_id: ^id} = Repo.reload(markt)
    end

    test "changing only the capitalisation adds no rule", c do
      rewe = payee_fixture(name: "rewe")
      book(c, rewe, 2)

      assert {:ok, %Payee{name: "Rewe"} = renamed} = Payees.rename(budget_scope(), rewe, " Rewe ")
      assert renamed.id == rewe.id
      assert rules(rewe) == []
      assert count_of(rewe) == 2
    end

    test "a new name keeps the old one as the payee's rule, and no other payee keeps it" do
      markt = payee_fixture(name: "REWE Markt")
      edeka = payee_fixture(name: "Edeka")
      rule!(edeka, :is, "rewe markt")

      assert {:ok, %Payee{name: "Rewe"}} = Payees.rename(budget_scope(), markt, "Rewe")
      assert rules(markt) == [{0, :is, "REWE Markt"}]
      assert rules(edeka) == []
    end

    test "no rule for an old name the payee's rules match already" do
      markt = payee_fixture(name: "REWE Markt 4711")
      rule!(markt, :starts_with, "REWE")

      assert {:ok, _renamed} = Payees.rename(budget_scope(), markt, "Rewe")
      assert rules(markt) == [{0, :starts_with, "REWE"}]
    end

    test "merging takes over the merged payee's rules after the payee's own, without repeats" do
      rewe = payee_fixture(name: "Rewe")
      markt = payee_fixture(name: "REWE Markt")
      rule!(rewe, :is, "REWE GmbH")
      rule!(markt, :is, "rewe gmbh", 0)
      rule!(markt, :contains, "Köln", 1)

      assert {:ok, _rewe} = Payees.rename(budget_scope(), markt, "Rewe")

      assert rules(rewe) == [
               {0, :is, "REWE GmbH"},
               {1, :contains, "Köln"},
               {2, :is, "REWE Markt"}
             ]
    end

    test "refuses a blank name, a transfer name and a transfer payee", c do
      rewe = payee_fixture(name: "Rewe")

      assert {:error, changeset} = Payees.rename(budget_scope(), rewe, "  ")
      assert %{name: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} = Payees.rename(budget_scope(), rewe, "transfer: Giro")

      assert %{
               name: [
                 "„transfer: Giro“ ist kein gültiger Empfängername. „Transfer :“ am Anfang ist " <>
                   "Umbuchungen vorbehalten."
               ]
             } = errors_on(changeset)

      assert Payees.rename(budget_scope(), c.giro.transfer_payee, "Bank") == {:error, :not_found}

      assert Repo.reload(rewe).name == "Rewe"
    end

    test "combining renames each payee into the name", c do
      nord = payee_fixture(name: "Aldi Nord")
      dankt = payee_fixture(name: "ALDI SAGT DANKE")
      aldi = payee_fixture(name: "Aldi")
      book(c, nord, 1)
      book(c, dankt, 2)
      book(c, aldi, 4)

      assert {:ok, %Payee{id: id, name: "Aldi"}} =
               Payees.combine(budget_scope(), [nord.id, dankt.id, aldi.id], "Aldi")

      assert id == aldi.id
      assert %{"Aldi" => %{transaction_count: 7}} = overview()
      assert map_size(overview()) == 1
      assert rules(aldi) == [{0, :is, "Aldi Nord"}, {1, :is, "ALDI SAGT DANKE"}]
    end

    test "combining under a new name renames the first and merges the others into it", c do
      nord = payee_fixture(name: "Aldi Nord")
      sued = payee_fixture(name: "Aldi Süd")

      assert {:ok, %Payee{id: id, name: "Aldi"}} =
               Payees.combine(
                 budget_scope(),
                 [nord.id, c.giro.transfer_payee.id, sued.id],
                 "Aldi"
               )

      assert id == nord.id
      assert rules(nord) == [{0, :is, "Aldi Nord"}, {1, :is, "Aldi Süd"}]
      assert Repo.reload(c.giro.transfer_payee).deleted_at == nil
    end

    test "combining refuses a name renaming refuses and leaves the payees alone" do
      nord = payee_fixture(name: "Aldi Nord")

      assert {:error, changeset} = Payees.combine(budget_scope(), [nord.id], "")
      assert %{name: ["can't be blank"]} = errors_on(changeset)
      assert Repo.reload(nord).name == "Aldi Nord"
    end

    test "set_hidden/3 hides and shows regular payees and skips transfer payees", c do
      rewe = payee_fixture(name: "Rewe")
      transfer = c.giro.transfer_payee

      assert :ok = Payees.set_hidden(budget_scope(), [rewe.id, transfer.id], true)
      assert Repo.reload(rewe).hidden
      refute Repo.reload(transfer).hidden

      assert :ok = Payees.set_hidden(budget_scope(), [rewe.id], false)
      refute Repo.reload(rewe).hidden
    end

    test "update_payee/3 sets and clears the payee's category" do
      rewe = payee_fixture(name: "Rewe")
      category = category_fixture()

      assert {:ok, %Payee{last_category_id: id}} =
               Ledger.update_payee(budget_scope(), rewe, %{last_category_id: category.id})

      assert id == category.id

      assert {:ok, %Payee{last_category_id: nil}} =
               Ledger.update_payee(budget_scope(), rewe, %{last_category_id: nil})
    end

    test "put_rename_conditions/3 stores the rules in order and drops blank ones" do
      rewe = payee_fixture(name: "Rewe")
      kept = rule!(rewe, :starts_with, "REWE Markt", 0)
      gone = rule!(rewe, :is, "Alt", 1)

      assert {:ok, [first, second]} =
               Payees.put_rename_conditions(budget_scope(), rewe, [
                 %{"operator" => "contains", "text" => "Köln"},
                 %{operator: :contains, text: "  "},
                 %{id: kept.id, operator: :starts_with, text: "REWE Markt"}
               ])

      assert {first.position, second.id} == {0, kept.id}
      assert rules(rewe) == [{0, :contains, "Köln"}, {1, :starts_with, "REWE Markt"}]
      assert %PayeeRenameCondition{deleted_at: %DateTime{}} = Repo.reload(gone)
    end

    test "put_rename_conditions/3 refuses an unknown operator and keeps the rules" do
      rewe = payee_fixture(name: "Rewe")
      rule!(rewe, :is, "REWE")

      assert {:error, changeset} =
               Payees.put_rename_conditions(budget_scope(), rewe, [
                 %{operator: "like", text: "REWE"}
               ])

      assert %{operator: ["is invalid"]} = errors_on(changeset)
      assert rules(rewe) == [{0, :is, "REWE"}]
    end

    test "rename_preview/2 counts the transactions the rules would rename and names their payees, unused ones too",
         c do
      rewe = payee_fixture(name: "Rewe")
      rule!(rewe, :starts_with, "REWE Markt")
      gmbh = payee_fixture(name: "REWE Markt GmbH 4711")
      koeln = payee_fixture(name: "REWE Markt Köln")
      unused = payee_fixture(name: "REWE Markt unbenutzt")
      book(c, rewe)
      book(c, gmbh, 2)

      {:ok, _split} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.giro.id,
          date: ~D[2026-10-10],
          amount: -300,
          subtransactions: [
            %{amount: -100, payee_id: gmbh.id},
            %{amount: -200, payee_id: koeln.id}
          ]
        })

      assert Payees.rename_preview(budget_scope(), rewe) ==
               {:ok,
                %{
                  transaction_count: 4,
                  payee_names: ["REWE Markt GmbH 4711", "REWE Markt Köln", "REWE Markt unbenutzt"],
                  payee_ids: [gmbh.id, koeln.id, unused.id]
                }}
    end

    test "rename_preview/2 sorts the names as the apps do, diacritics and case after the letters",
         c do
      target = payee_fixture(name: "Ziel")
      rule!(target, :contains, "o", 0)
      rule!(target, :contains, "ä", 1)
      rule!(target, :contains, "a", 2)

      for name <- ["Zoo", "Ärztehaus", "arztpraxis", "Apotheke"],
          do: book(c, payee_fixture(name: name))

      assert {:ok, %{payee_names: ["Apotheke", "Ärztehaus", "arztpraxis", "Zoo"]}} =
               Payees.rename_preview(budget_scope(), target)
    end

    test "rename_preview/2 finds nothing for rules that match no payee", c do
      rewe = payee_fixture(name: "Rewe")
      rule!(rewe, :is, "Nirgendwo")
      book(c, rewe)

      assert Payees.rename_preview(budget_scope(), rewe) ==
               {:ok, %{transaction_count: 0, payee_names: [], payee_ids: []}}
    end

    test "apply_rename_rules/2 renames the matched transactions to the payee", c do
      rewe = payee_fixture(name: "Rewe")
      rule!(rewe, :starts_with, "REWE Markt")
      gmbh = payee_fixture(name: "REWE Markt GmbH 4711")
      koeln = payee_fixture(name: "REWE Markt Köln")
      book(c, gmbh, 3)
      book(c, koeln, 1)

      assert {:ok, %Payee{id: id}} =
               Payees.apply_rename_rules(budget_scope(), rewe, [koeln.id, gmbh.id])

      assert id == rewe.id
      assert count_of(rewe) == 4
      assert rules(rewe) == [{0, :starts_with, "REWE Markt"}]
      assert Repo.reload(gmbh).deleted_at
      assert Repo.reload(koeln).successor_id == rewe.id
    end

    test "rename_preview/2 and apply_rename_rules/3 take in a matching payee nothing uses" do
      booking = payee_fixture(name: "Booking.com")
      rule!(booking, :starts_with, "partners on booking bv")
      partners = payee_fixture(name: "Partners on Booking BV, Amsterdam; NL")

      assert Payees.rename_preview(budget_scope(), booking) ==
               {:ok,
                %{
                  transaction_count: 0,
                  payee_names: ["Partners on Booking BV, Amsterdam; NL"],
                  payee_ids: [partners.id]
                }}

      assert {:ok, %Payee{id: id}} =
               Payees.apply_rename_rules(budget_scope(), booking, [partners.id])

      assert id == booking.id
      assert Repo.reload(partners).successor_id == booking.id

      assert Payees.rename_preview(budget_scope(), booking) ==
               {:ok, %{transaction_count: 0, payee_names: [], payee_ids: []}}
    end

    test "apply_rename_rules/3 renames nothing when the matched payees are not the previewed ones",
         c do
      rewe = payee_fixture(name: "Rewe")
      rule!(rewe, :starts_with, "REWE Markt")
      gmbh = payee_fixture(name: "REWE Markt GmbH 4711")
      koeln = payee_fixture(name: "REWE Markt Köln")
      book(c, gmbh)
      book(c, koeln)

      assert Payees.apply_rename_rules(budget_scope(), rewe, [gmbh.id]) == {:error, :changed}
      assert Payees.apply_rename_rules(budget_scope(), rewe, []) == {:error, :changed}
      assert count_of(rewe) == 0
      refute Repo.reload(gmbh).deleted_at
    end

    test "a payee that is gone or a transfer payee is not found", c do
      rewe = payee_fixture(name: "Rewe")
      {:ok, _aldi} = Payees.rename(budget_scope(), payee_fixture(name: "Aldi"), "Edeka")
      {:ok, _merged} = Payees.rename(budget_scope(), rewe, "Edeka")
      transfer = c.giro.transfer_payee

      for payee <- [rewe, transfer] do
        assert Payees.rename(budget_scope(), payee, "Neu") == {:error, :not_found}
        assert Payees.put_rename_conditions(budget_scope(), payee, []) == {:error, :not_found}
        assert Payees.rename_preview(budget_scope(), payee) == {:error, :not_found}
        assert Payees.apply_rename_rules(budget_scope(), payee, []) == {:error, :not_found}
      end

      assert Ledger.update_payee(budget_scope(), rewe, %{last_category_id: nil}) ==
               {:error, :not_found}
    end

    test "a payee's new rule goes after its last one, whatever the positions" do
      markt = payee_fixture(name: "REWE Markt")
      rule!(markt, :contains, "Köln", 3)

      assert {:ok, _renamed} = Payees.rename(budget_scope(), markt, "Rewe")
      assert rules(markt) == [{3, :contains, "Köln"}, {4, :is, "REWE Markt"}]
    end

    test "put_rename_conditions/3 refuses a rule text longer than 200 characters" do
      rewe = payee_fixture(name: "Rewe")

      assert {:error, changeset} =
               Payees.put_rename_conditions(budget_scope(), rewe, [
                 %{operator: :contains, text: String.duplicate("a", 201)}
               ])

      assert %{text: ["should be at most 200 character(s)"]} = errors_on(changeset)
    end

    test "merge_payee/3 refuses another user's payees" do
      mine = payee_fixture(name: "Rewe")
      other = user_scope_fixture()
      {:ok, theirs} = Ledger.create_payee(other, %{name: "Aldi"})

      assert_raise Ecto.NoResultsError, fn -> Ledger.merge_payee(budget_scope(), theirs, mine) end
      assert_raise Ecto.NoResultsError, fn -> Ledger.merge_payee(budget_scope(), mine, theirs) end
      refute Repo.reload(theirs).deleted_at
      refute Repo.reload(mine).deleted_at
    end

    test "another user's payees are refused or left alone" do
      rewe = payee_fixture(name: "Rewe")
      other = user_scope_fixture()

      assert Payees.list(other) == []
      assert Payees.rename(other, rewe, "Meins") == {:error, :not_found}
      assert Payees.put_rename_conditions(other, rewe, []) == {:error, :not_found}
      assert Payees.rename_preview(other, rewe) == {:error, :not_found}
      assert Payees.apply_rename_rules(other, rewe, []) == {:error, :not_found}
      assert {:ok, nil} = Payees.combine(other, [rewe.id], "Meins")
      assert :ok = Payees.set_hidden(other, [rewe.id], true)

      assert %Payee{name: "Rewe", hidden: false} = Repo.reload(rewe)
    end

    test "put_rename_conditions/3 leaves another user's rule alone when given its id" do
      other = user_scope_fixture()
      {:ok, theirs} = Ledger.create_payee(other, %{name: "Fremd"})

      {:ok, [their_rule]} =
        Payees.put_rename_conditions(other, theirs, [%{operator: :is, text: "X"}])

      rewe = payee_fixture(name: "Rewe")

      assert {:ok, [mine]} =
               Payees.put_rename_conditions(budget_scope(), rewe, [
                 %{id: their_rule.id, operator: :contains, text: "REWE"}
               ])

      assert mine.id != their_rule.id

      assert %PayeeRenameCondition{payee_id: payee_id, text: "X", deleted_at: nil} =
               Repo.reload(their_rule)

      assert payee_id == theirs.id
    end

    test "renamer/1 renames a name a regular payee's rule matches and keeps others" do
      rewe = payee_fixture(name: "Rewe")
      rule!(rewe, :starts_with, "rewe markt")
      rename = Payees.renamer(budget_scope())

      assert rename.("REWE Markt GmbH 4711") == "Rewe"
      assert rename.("Aldi") == "Aldi"
      assert rename.(nil) == nil
    end

    test "renamer/1 takes the first payee by lookup key, and within it the topmost rule" do
      edeka = payee_fixture(name: "Edeka")
      rewe = payee_fixture(name: "Rewe")
      rule!(rewe, :starts_with, "REWE")
      rule!(edeka, :is, "REWE Markt", 1)
      rule!(edeka, :contains, "Markt", 0)

      assert Payees.renamer(budget_scope()).("REWE Markt") == "Edeka"
    end

    test "renamer/1 leaves out the rules of transfer payees and deleted ones", c do
      rule!(c.giro.transfer_payee, :is, "Umbuchung Tagesgeld")
      rewe = payee_fixture(name: "Rewe")

      rewe
      |> rule!(:is, "REWE Markt")
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
      |> Repo.update!()

      rename = Payees.renamer(budget_scope())

      assert rename.("Umbuchung Tagesgeld") == "Umbuchung Tagesgeld"
      assert rename.("REWE Markt") == "REWE Markt"
      assert Payees.renamer(user_scope_fixture()).("REWE Markt") == "REWE Markt"
    end

    test "the writes become sync messages", c do
      rewe = payee_fixture(name: "Rewe")
      markt = payee_fixture(name: "REWE Markt")
      [booked] = book(c, markt)
      cursor = Abakus.Sync.cursor(budget_scope())

      {:ok, _rewe} = Payees.rename(budget_scope(), markt, "Rewe")
      :ok = Payees.set_hidden(budget_scope(), [rewe.id], true)

      payees = messages_after(cursor, "payees")
      assert {markt.id, "successor_id", ~s("#{rewe.id}")} in payees
      assert {rewe.id, "hidden", "true"} in payees
      assert {booked.id, "payee_id", ~s("#{rewe.id}")} in messages_after(cursor, "transactions")

      assert [{_id, "text", ~s("REWE Markt")}] =
               cursor
               |> messages_after("payee_rename_conditions")
               |> Enum.filter(&(elem(&1, 1) == "text"))
    end

    test "storing rules writes inserts, moves and tombstones as sync messages" do
      rewe = payee_fixture(name: "Rewe")
      moved = rule!(rewe, :starts_with, "REWE", 0)
      gone = rule!(rewe, :is, "Alt", 1)
      cursor = Abakus.Sync.cursor(budget_scope())

      {:ok, [added, %{id: moved_id}]} =
        Payees.put_rename_conditions(budget_scope(), rewe, [
          %{operator: :contains, text: "Köln"},
          %{id: moved.id, operator: :starts_with, text: "REWE"}
        ])

      messages = messages_after(cursor, "payee_rename_conditions")
      assert {added.id, "text", ~s("Köln")} in messages
      assert {added.id, "payee_id", ~s("#{rewe.id}")} in messages
      assert {moved_id, "position", "1"} in messages
      assert moved_id == moved.id
      assert Enum.any?(messages, &match?({id, "deleted_at", _at} when id == gone.id, &1))
    end

    test "combining, renaming by the rules and setting the category write sync messages", c do
      aldi = payee_fixture(name: "Aldi")
      nord = payee_fixture(name: "Aldi Nord")
      markt = payee_fixture(name: "Aldi Markt")
      [combined] = book(c, nord)
      [renamed] = book(c, markt)
      category = category_fixture()
      cursor = Abakus.Sync.cursor(budget_scope())

      {:ok, _aldi} = Payees.combine(budget_scope(), [nord.id], "Aldi")

      {:ok, _rules} =
        Payees.put_rename_conditions(budget_scope(), aldi, [%{operator: :contains, text: "Markt"}])

      {:ok, _aldi} = Payees.apply_rename_rules(budget_scope(), aldi, [markt.id])
      {:ok, _aldi} = Ledger.update_payee(budget_scope(), aldi, %{last_category_id: category.id})

      payees = messages_after(cursor, "payees")
      assert {nord.id, "successor_id", ~s("#{aldi.id}")} in payees
      assert {markt.id, "successor_id", ~s("#{aldi.id}")} in payees
      assert {aldi.id, "last_category_id", ~s("#{category.id}")} in payees

      transactions = messages_after(cursor, "transactions")
      assert {combined.id, "payee_id", ~s("#{aldi.id}")} in transactions
      assert {renamed.id, "payee_id", ~s("#{aldi.id}")} in transactions
    end
  end
end

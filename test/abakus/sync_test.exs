defmodule Abakus.SyncTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ids, Import, Ledger, Sync, SyncDevice, UsersFixtures}
  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Payee, Scheduled, ScheduledTransaction, Subtransaction, Transaction}
  alias Abakus.Sync.{FieldClock, Message, Tables}
  alias Abakus.Users.Scope

  @mac "2026-11-02T10:05:00.000Z-0000-mac"

  setup do
    fix_now(~U[2026-11-02 10:00:00Z])
    %{scope: budget_scope(), giro: account_fixture(name: "Girokonto")}
  end

  defp messages_after(cursor),
    do: Repo.all(from m in Message, where: m.id > ^cursor, order_by: m.id)

  defp fields(messages), do: Enum.map(messages, &{&1.table, &1.column, JSON.decode!(&1.value)})

  defp message(row_id, column, value, clock \\ @mac, table \\ "transactions"),
    do: %{
      "table" => table,
      "row_id" => row_id,
      "column" => column,
      "value" => value,
      "clock" => clock
    }

  describe "writes" do
    test "a new row is a message for each field that has a value, all with the server's clock",
         c do
      cursor = Sync.cursor(c.scope)
      transaction = transaction_fixture(account_id: c.giro.id, amount: -650, date: ~D[2026-11-02])

      messages = messages_after(cursor)

      assert Enum.sort(fields(messages)) ==
               Enum.sort([
                 {"transactions", "account_id", c.giro.id},
                 {"transactions", "date", "2026-11-02"},
                 {"transactions", "amount", -650},
                 {"transactions", "cleared", "uncleared"},
                 {"transactions", "approved", true},
                 {"transactions", "source", "manual"}
               ])

      assert [%{clock: clock, device: "server", user_id: user_id}] =
               Enum.uniq_by(messages, &{&1.clock, &1.device, &1.user_id})

      assert clock =~ ~r/\A2026-11-02T10:00:00.000Z-[0-9a-f]{4}-server\z/
      assert user_id == c.scope.user.id
      assert Enum.all?(messages, &(&1.row_id == transaction.id))
    end

    test "a change is a message for each changed field, and the field's clock follows it", c do
      transaction = transaction_fixture(account_id: c.giro.id)
      cursor = Sync.cursor(c.scope)

      {:ok, _} =
        Ledger.update_transaction(c.scope, transaction, %{memo: "Brötchen", amount: -1_250})

      assert [%Message{column: "memo", value: ~s("Brötchen"), clock: clock}] =
               messages_after(cursor)

      assert Repo.get_by!(FieldClock,
               table: "transactions",
               row_id: transaction.id,
               column: "memo"
             ).clock ==
               clock
    end

    test "nothing changed writes nothing", c do
      transaction = transaction_fixture(account_id: c.giro.id, memo: "Gleich")
      cursor = Sync.cursor(c.scope)

      {:ok, _} = Ledger.update_transaction(c.scope, transaction, %{memo: "Gleich"})

      assert messages_after(cursor) == []
    end

    test "the clock moves on from the newest one stored, a device's included", c do
      transaction = transaction_fixture(account_id: c.giro.id)
      {:ok, _} = Sync.apply_messages(c.scope, "mac", [message(transaction.id, "memo", "Mac")])

      {:ok, _} = Ledger.update_transaction(c.scope, transaction, %{memo: "Web"})

      assert %Transaction{memo: "Web"} = Repo.reload(transaction)

      assert [%{clock: "2026-11-02T10:05:00.000Z-0001-server"}] =
               messages_after(Sync.cursor(c.scope) - 1)
    end

    test "a transfer's two sides share one clock", c do
      savings = account_fixture(kind: :savings)
      cursor = Sync.cursor(c.scope)

      transaction_fixture(account_id: c.giro.id, payee_id: savings.transfer_payee.id)

      assert [_one_clock] = messages_after(cursor) |> Enum.map(& &1.clock) |> Enum.uniq()
      assert messages_after(cursor) |> Enum.map(& &1.row_id) |> Enum.uniq() |> length() == 2
    end

    test "an import is one write with one clock", c do
      cursor = Sync.cursor(c.scope)

      entries =
        for {id, payee} <- [{"A", "Bäcker"}, {"B", "Metzger"}] do
          %{external_id: id, date: ~D[2026-11-02], amount: -500, payee_name: payee, memo: nil}
        end

      {:ok, %{new: 2}} = Import.import(c.scope, c.giro, :file, entries)

      assert [_one_clock] = messages_after(cursor) |> Enum.map(& &1.clock) |> Enum.uniq()
      assert messages_after(cursor) |> Enum.map(& &1.row_id) |> Enum.uniq() |> length() == 4
    end

    test "a part removed from a split is deleted, not removed", c do
      split =
        transaction_fixture(
          account_id: c.giro.id,
          amount: -1_000,
          subtransactions: [%{amount: -600}, %{amount: -400}]
        )

      [first, second] = Ledger.get_transaction!(c.scope, split.id).subtransactions
      cursor = Sync.cursor(c.scope)

      {:ok, _} =
        Ledger.update_transaction(c.scope, split, %{
          subtransactions: [%{id: first.id, amount: -1_000}, %{amount: 0}]
        })

      assert %Subtransaction{deleted_at: %DateTime{}} = Repo.reload(second)

      assert {"subtransactions", "deleted_at", _now} =
               List.keyfind(fields(messages_after(cursor)), "deleted_at", 1)

      assert [_kept, _new] = Ledger.get_transaction!(c.scope, split.id).subtransactions
    end

    test "a write that is refused leaves no messages", c do
      cursor = Sync.cursor(c.scope)

      assert {:error, _changeset} =
               Ledger.create_transaction(c.scope, %{account_id: c.giro.id, date: nil, amount: 1})

      assert messages_after(cursor) == []
    end

    test "parts and counterparts of an entered occurrence are named after it", c do
      savings = account_fixture(kind: :savings)

      scheduled =
        Repo.insert!(%ScheduledTransaction{
          user_id: c.scope.user.id,
          account_id: c.giro.id,
          next_date: ~D[2026-12-01],
          frequency: :monthly,
          amount: -1_000
        })

      {:ok, transaction} =
        Ledger.create_transaction(
          c.scope,
          %{
            account_id: c.giro.id,
            date: ~D[2026-12-01],
            amount: -1_000,
            subtransactions: [
              %{amount: -600},
              %{amount: -400, payee_id: savings.transfer_payee.id}
            ]
          },
          entered_from: {scheduled.id, ~D[2026-12-01]}
        )

      [first, second] = Ledger.get_transaction!(c.scope, transaction.id).subtransactions
      assert first.id == Ids.entered_subtransaction(transaction.id, 0)
      assert second.id == Ids.entered_subtransaction(transaction.id, 1)
      assert second.transfer_transaction_id == Ids.transfer_counterpart(second.id)
    end
  end

  describe "telling waiting devices" do
    test "a write tells them once it has committed, but not the LiveViews", c do
      Sync.subscribe_messages(c.scope)
      Sync.subscribe(c.scope)

      transaction_fixture(account_id: c.giro.id)

      assert_received {:written, "server"}
      refute_received {:synced, _device}
    end

    test "a write within a transaction tells them once that commits, once", c do
      Sync.subscribe_messages(c.scope)

      {:ok, _} =
        Repo.transact(fn ->
          transaction_fixture(account_id: c.giro.id)
          transaction_fixture(account_id: c.giro.id)
          refute_received {:written, _writer}
          {:ok, nil}
        end)

      assert_received {:written, "server"}
      refute_received {:written, _writer}
    end

    test "a write that rolls back tells no one", c do
      Sync.subscribe_messages(c.scope)

      {:error, :undone} =
        Repo.transact(fn ->
          transaction_fixture(account_id: c.giro.id)
          {:error, :undone}
        end)

      refute_received {:written, _writer}
    end

    test "a device's push tells them and the LiveViews", c do
      rewe = transaction_fixture(account_id: c.giro.id)
      Sync.subscribe_messages(c.scope)
      Sync.subscribe(c.scope)

      {:ok, 1} = Sync.apply_messages(c.scope, "mac", [message(rewe.id, "memo", "Mac")])

      assert_received {:written, "mac"}
      assert_received {:synced, "mac"}
    end
  end

  describe "snapshot" do
    test "every synced row of the user with its fields, their clocks and the cursor", c do
      transaction = transaction_fixture(account_id: c.giro.id, memo: "Rewe")
      {:ok, 1} = Sync.apply_messages(c.scope, "mac", [message(transaction.id, "memo", "Mac")])
      other = Scope.for_user(UsersFixtures.user_fixture())
      Repo.insert!(%Payee{user_id: other.user.id, name: "Fremd", lookup_key: "fremd"})

      snapshot = Sync.snapshot(c.scope)

      assert snapshot.cursor == Sync.cursor(c.scope)
      assert [row] = Enum.filter(snapshot.tables["transactions"], &(&1.id == transaction.id))
      assert %{"memo" => "Mac", "amount" => -1_250, "account_id" => giro} = row.fields
      assert giro == c.giro.id
      assert row.clocks["memo"] == @mac
      assert row.clocks["amount"] =~ "-server"
      refute Map.has_key?(row.fields, "user_id")
      refute Enum.any?(snapshot.tables["payees"], &(&1.fields["name"] == "Fremd"))

      assert Map.keys(snapshot.tables) |> Enum.sort() ==
               Enum.sort(Enum.map(Tables.schemas(), &Tables.table/1))
    end

    test "has Ready to Assign and its group for an owner who never opened the budget" do
      scope = Scope.for_user(UsersFixtures.user_fixture())

      snapshot = Sync.snapshot(scope)

      assert [%{fields: %{"internal" => true}}] = snapshot.tables["category_groups"]
      assert [%{fields: %{"internal" => true}, id: id}] = snapshot.tables["categories"]
      assert id == Categories.ready_to_assign!(scope).id
    end
  end

  describe "applying messages" do
    setup c do
      %{rewe: transaction_fixture(account_id: c.giro.id, memo: "Rewe")}
    end

    test "a newer message changes its field, an older one is stored but changes nothing", c do
      older = "2026-11-02T09:00:00.000Z-0000-mac"

      assert {:ok, 2} =
               Sync.apply_messages(c.scope, "mac", [
                 message(c.rewe.id, "memo", "Mac"),
                 message(c.rewe.id, "amount", 1, older)
               ])

      assert %Transaction{memo: "Mac", amount: -1_250} = Repo.reload(c.rewe)

      assert Repo.get_by!(FieldClock, table: "transactions", row_id: c.rewe.id, column: "memo").clock ==
               @mac
    end

    test "no messages change nothing, not even what the server settles after messages", c do
      one = category_fixture()
      two = category_fixture()
      now = DateTime.utc_now()

      for {category, successor} <- [{one, two}, {two, one}],
          do:
            category
            |> Ecto.Changeset.change(deleted_at: now, successor_id: successor.id)
            |> Repo.update!()

      cursor = Sync.cursor(c.scope)

      assert {:ok, 0} = Sync.apply_messages(c.scope, "mac", [])
      assert Sync.cursor(c.scope) == cursor
      assert Repo.reload(one).deleted_at
    end

    test "a message stored already is ignored", c do
      assert {:ok, 1} = Sync.apply_messages(c.scope, "mac", [message(c.rewe.id, "memo", "Mac")])
      assert {:ok, 0} = Sync.apply_messages(c.scope, "mac", [message(c.rewe.id, "memo", "Mac")])
    end

    test "tables and columns the server does not sync are ignored", c do
      assert {:ok, 0} =
               Sync.apply_messages(c.scope, "mac", [
                 message(c.rewe.id, "kasse_expense_id", 1),
                 message(c.rewe.id, "user_id", 2),
                 message(c.rewe.id, "name", "x", @mac, "users")
               ])
    end

    test "refuses a clock of another device, a bad clock, row id or value", c do
      assert {:error, {:invalid_clock, _}} =
               Sync.apply_messages(c.scope, "ipad", [message(c.rewe.id, "memo", "x")])

      assert {:error, {:invalid_clock, _}} =
               Sync.apply_messages(c.scope, "mac", [message(c.rewe.id, "memo", "x", "gestern")])

      assert {:error, {:invalid_row_id, _}} =
               Sync.apply_messages(c.scope, "mac", [message("7", "memo", "x")])

      assert {:error, {:invalid_value, "transactions", "amount", "viel"}} =
               Sync.apply_messages(c.scope, "mac", [message(c.rewe.id, "amount", "viel")])

      assert Repo.reload(c.rewe).memo == "Rewe"
    end

    test "refuses a message without a value, as null is a value of its own", c do
      without_value = Map.delete(message(c.rewe.id, "memo", nil), "value")

      assert {:error, {:invalid_message, ^without_value}} =
               Sync.apply_messages(c.scope, "mac", [without_value])

      assert Repo.reload(c.rewe).memo == "Rewe"
    end

    test "an account a device creates without its transfer payee gets one", c do
      id = Ids.generate()

      {:ok, _stored} =
        Sync.apply_messages(c.scope, "mac", [
          message(id, "name", "Tagesgeld", @mac, "accounts"),
          message(id, "kind", "savings", @mac, "accounts")
        ])

      assert %Payee{name: "Transfer : Tagesgeld", transfer_account_id: ^id} =
               Repo.get!(Payee, Ids.transfer_payee(id))

      account = Ledger.get_account!(c.scope, id)
      assert {:ok, _renamed} = Ledger.update_account(c.scope, account, %{name: "Notgroschen"})
    end

    test "refuses a push whole when a clock runs more than five minutes ahead", c do
      in_time = "2026-11-02T10:05:00.000Z-0000-mac"
      ahead = "2026-11-02T10:05:00.001Z-0000-mac"

      assert {:error, {:clock_ahead, ^ahead}} =
               Sync.apply_messages(c.scope, "mac", [
                 message(c.rewe.id, "memo", "Mac", in_time),
                 message(c.rewe.id, "amount", 1, ahead)
               ])

      assert %Transaction{memo: "Rewe"} = Repo.reload(c.rewe)

      assert {:ok, 1} =
               Sync.apply_messages(c.scope, "mac", [message(c.rewe.id, "memo", "Mac", in_time)])
    end

    test "a row that does not exist yet is created for the user, a name with its lookup key", c do
      id = Ids.generate()

      {:ok, 2} =
        Sync.apply_messages(c.scope, "mac", [
          message(id, "name", "🥖 Bäckerei Korn", @mac, "payees"),
          message(id, "hidden", false, @mac, "payees")
        ])

      assert %Payee{user_id: user_id, lookup_key: "bäckerei korn"} = Repo.get!(Payee, id)
      assert user_id == c.scope.user.id
    end

    test "refuses a push whole that leaves a row pointing at none", c do
      id = Ids.generate()

      assert {:error, {:rejected, detail}} =
               Sync.apply_messages(c.scope, "mac", [
                 message(c.rewe.id, "memo", "Mac"),
                 message(id, "account_id", Ids.generate()),
                 message(id, "date", "2026-11-02"),
                 message(id, "amount", -100)
               ])

      assert detail =~ "transactions"
      assert Repo.reload(c.rewe).memo == "Rewe"
      refute Repo.get(Transaction, id)
    end

    test "a twice-a-month schedule may lack its days, and is entered monthly", c do
      scheduled =
        Repo.insert!(%ScheduledTransaction{
          user_id: c.scope.user.id,
          account_id: c.giro.id,
          next_date: ~D[2026-11-02],
          frequency: :monthly,
          amount: -1_000
        })

      assert {:ok, 1} =
               Sync.apply_messages(c.scope, "mac", [
                 message(
                   scheduled.id,
                   "frequency",
                   "twice_a_month",
                   @mac,
                   "scheduled_transactions"
                 )
               ])

      assert {:ok, 1} = Scheduled.enter_due(c.scope, ~D[2026-11-02])
      assert Repo.reload(scheduled).next_date == ~D[2026-12-02]
    end

    test "a reference to a merged payee points at the end of its chain of successors", c do
      [last, middle, first] = for name <- ~w(Korn Bäcker Bäckerei), do: payee_fixture(name: name)
      now = DateTime.utc_now()

      for {payee, successor} <- [{first, middle}, {middle, last}],
          do:
            payee
            |> Ecto.Changeset.change(deleted_at: now, successor_id: successor.id)
            |> Repo.update!()

      created = Ids.generate()

      {:ok, _stored} =
        Sync.apply_messages(c.scope, "mac", [
          message(c.rewe.id, "payee_id", first.id),
          message(created, "account_id", c.giro.id),
          message(created, "date", "2026-11-02"),
          message(created, "amount", -100),
          message(created, "payee_id", middle.id)
        ])

      assert Repo.reload(c.rewe).payee_id == last.id
      assert Repo.get!(Transaction, created).payee_id == last.id
    end

    test "a message for another user's row is dropped", c do
      other = Scope.for_user(UsersFixtures.user_fixture())

      assert {:ok, 0} = Sync.apply_messages(other, "mac", [message(c.rewe.id, "memo", "Fremd")])
      assert Repo.reload(c.rewe).memo == "Rewe"
    end

    test "a message pointing at another user's row is dropped", c do
      other = Scope.for_user(UsersFixtures.user_fixture())
      {:ok, theirs} = Ledger.create_account(other, %{name: "Fremd", kind: :checking})

      assert {:ok, 1} =
               Sync.apply_messages(c.scope, "mac", [
                 message(c.rewe.id, "account_id", theirs.id),
                 message(c.rewe.id, "memo", "Mac")
               ])

      assert %Transaction{memo: "Mac", account_id: account_id} = Repo.reload(c.rewe)
      assert account_id == c.giro.id
    end

    test "a part belongs to the owner of its transaction", c do
      other = Scope.for_user(UsersFixtures.user_fixture())
      part = Ids.generate()

      messages = [
        message(part, "transaction_id", c.rewe.id, @mac, "subtransactions"),
        message(part, "amount", -1_250, @mac, "subtransactions")
      ]

      assert {:ok, 0} = Sync.apply_messages(other, "mac", messages)
      assert {:ok, 2} = Sync.apply_messages(c.scope, "mac", messages)
      assert Repo.get!(Subtransaction, part).transaction_id == c.rewe.id
    end

    test "the user's LiveViews hear of it, and other devices read it after their cursor", c do
      Sync.subscribe(c.scope)
      cursor = Sync.cursor(c.scope)

      {:ok, 1} = Sync.apply_messages(c.scope, "mac", [message(c.rewe.id, "memo", "Mac")])

      assert_received {:synced, "mac"}

      assert [%Message{column: "memo", device: "mac"}] =
               SyncDevice.messages_after(c.scope, cursor, "ipad")

      assert SyncDevice.messages_after(c.scope, cursor, "mac") == []
    end

    test "a pull reads up to a limit of all devices' messages and says whether there are more",
         c do
      cursor = Sync.cursor(c.scope)
      {:ok, 1} = Sync.apply_messages(c.scope, "mac", [message(c.rewe.id, "memo", "Mac")])
      {:ok, _} = Ledger.update_transaction(c.scope, c.rewe, %{amount: -100})
      {:ok, _} = Ledger.update_transaction(c.scope, Repo.reload(c.rewe), %{amount: -200})
      last = Sync.cursor(c.scope)

      assert {[%Message{device: "server"}], second, true} = Sync.pull(c.scope, cursor, "mac", 2)
      assert second == last - 1
      assert {[%Message{device: "server"}], ^last, false} = Sync.pull(c.scope, second, "mac", 2)
      assert {[], ^last, false} = Sync.pull(c.scope, last, "mac", 2)
    end

    test "a category deleted into another in a cycle comes back", c do
      one = category_fixture()
      two = category_fixture()
      {:ok, _} = Categories.delete_category(c.scope, one, two)
      [first, second] = Enum.sort([one.id, two.id])
      at = "2026-11-02T10:05:00.000Z-0000-mac"

      {:ok, _} =
        Sync.apply_messages(c.scope, "mac", [
          message(two.id, "deleted_at", "2026-11-02T10:05:00.000000Z", at, "categories"),
          message(two.id, "successor_id", one.id, at, "categories")
        ])

      assert Repo.get!(Category, first).deleted_at == nil
      assert Repo.get!(Category, second).deleted_at
    end
  end
end

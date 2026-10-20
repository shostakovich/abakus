defmodule Abakus.BankSyncTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.BankSyncFixtures
  import ExUnit.CaptureLog

  alias Abakus.{BankSync, Ledger, Repo}
  alias Abakus.BankSync.{AccessError, Connection, FakeClient, LinkedAccount}
  alias Abakus.Ledger.TransactionOrigin
  alias Abakus.Users.Scope

  setup do
    FakeClient.serve()
    fix_now(~U[2026-10-20 10:00:00.000000Z])
  end

  describe "available?/0" do
    test "says whether the client is configured" do
      assert BankSync.available?()
      stop_supervised!(FakeClient)
      refute BankSync.available?()
    end
  end

  describe "banks/2" do
    test "lists a country's banks by name" do
      assert {:ok, [%{name: "Musterbank"}, %{name: "Sparkasse Musterstadt"}]} =
               BankSync.banks(budget_scope(), "DE")
    end
  end

  describe "authorize/3" do
    test "starts a consent until the longest the bank allows, with a random state" do
      assert {:ok, %{url: url, auth: auth}} =
               BankSync.authorize(
                 budget_scope(),
                 %{name: "Sparkasse Musterstadt", country: "DE"},
                 "https://abakus.example/callback"
               )

      assert [request] = FakeClient.auth_requests()
      assert url == "https://enablebanking.example/auth/#{auth.state}"
      assert request.state == auth.state
      assert byte_size(auth.state) >= 43
      assert request.bank == %{name: "Sparkasse Musterstadt", country: "DE"}
      assert request.redirect_url == "https://abakus.example/callback"
      assert request.valid_until == auth.valid_until
      assert auth.valid_until == ~U[2027-01-18 10:00:00Z]
      assert {auth.bank_name, auth.bank_country} == {"Sparkasse Musterstadt", "DE"}

      {:ok, %{auth: again}} =
        BankSync.authorize(
          budget_scope(),
          %{name: "Musterbank", country: "DE"},
          "https://abakus.example/callback"
        )

      assert again.state != auth.state
    end

    test "refuses a bank the country does not have" do
      assert BankSync.authorize(
               budget_scope(),
               %{name: "Musterbank", country: "FR"},
               "https://abakus.example/callback"
             ) == {:error, :unknown_bank}

      assert FakeClient.auth_requests() == []
    end
  end

  describe "connect/3" do
    test "keeps the connection with the bank's accounts, unlinked" do
      connection = connection_fixture()

      assert %{
               provider: :enable_banking,
               bank_name: "Musterbank",
               bank_country: "DE",
               session_id: "session-1",
               valid_until: ~U[2027-04-18 10:00:00.000000Z],
               reminders_sent: []
             } = connection

      assert [
               %{provider_account_id: "uid-giro", name: "Girokonto", account_id: nil},
               %{provider_account_id: "uid-savings", iban: "DE02100200300000004712"}
             ] = connection.linked_accounts

      assert BankSync.list_connections(budget_scope()) == [connection]
    end

    test "keeps the requested end of the consent when the session has none" do
      FakeClient.put_session("code-1", %{FakeClient.session() | valid_until: nil})
      connection = connection_fixture()

      assert connection.valid_until == ~U[2027-04-18 10:00:00.000000Z]
    end

    test "refuses a code the bank does not know" do
      {:ok, %{auth: auth}} =
        BankSync.authorize(budget_scope(), %{name: "Musterbank", country: "DE"}, "https://x")

      assert BankSync.connect(budget_scope(), auth, "unknown") == {:error, {:http_status, 400}}
      assert BankSync.list_connections(budget_scope()) == []
    end
  end

  describe "start_date/2" do
    test "is the day after the newest reconciled transaction, else today" do
      giro = account_fixture()
      transaction_fixture(account_id: giro.id, date: ~D[2026-09-30], cleared: :reconciled)
      transaction_fixture(account_id: giro.id, date: ~D[2026-10-01], cleared: :reconciled)
      transaction_fixture(account_id: giro.id, date: ~D[2026-10-05], cleared: :cleared)

      assert BankSync.start_date(budget_scope(), giro) == ~D[2026-10-02]
      assert BankSync.start_date(budget_scope(), account_fixture()) == ~D[2026-10-20]
    end
  end

  describe "assign_accounts/3" do
    setup do
      connection = connection_fixture()
      [current, savings] = connection.linked_accounts

      %{
        connection: connection,
        current: current,
        savings: savings,
        giro: account_fixture(name: "Girokonto"),
        tagesgeld: account_fixture(name: "Tagesgeld")
      }
    end

    test "links accounts from their start dates and leaves the others unlinked", ctx do
      assert {:ok, connection} =
               BankSync.assign_accounts(budget_scope(), ctx.connection, %{
                 ctx.current.id => %{account_id: ctx.giro.id, start_date: ~D[2026-10-02]},
                 ctx.savings.id => %{account_id: nil, start_date: ~D[2026-10-02]}
               })

      assert [current, savings] = connection.linked_accounts
      assert {current.account_id, current.start_date} == {ctx.giro.id, ~D[2026-10-02]}
      assert current.account.name == "Girokonto"
      assert {savings.account_id, savings.start_date} == {nil, nil}
    end

    test "lets two bank accounts swap their accounts", ctx do
      {:ok, _connection} =
        BankSync.assign_accounts(budget_scope(), ctx.connection, %{
          ctx.current.id => %{account_id: ctx.giro.id, start_date: ~D[2026-10-02]},
          ctx.savings.id => %{account_id: ctx.tagesgeld.id, start_date: ~D[2026-10-02]}
        })

      assert {:ok, connection} =
               BankSync.assign_accounts(budget_scope(), ctx.connection, %{
                 ctx.current.id => %{account_id: ctx.tagesgeld.id, start_date: ~D[2026-10-02]},
                 ctx.savings.id => %{account_id: ctx.giro.id, start_date: ~D[2026-10-02]}
               })

      assert Enum.map(connection.linked_accounts, & &1.account_id) ==
               [ctx.tagesgeld.id, ctx.giro.id]
    end

    test "refuses an account fed by another bank account, all or none", ctx do
      assert BankSync.assign_accounts(budget_scope(), ctx.connection, %{
               ctx.current.id => %{account_id: ctx.giro.id, start_date: ~D[2026-10-02]},
               ctx.savings.id => %{account_id: ctx.giro.id, start_date: ~D[2026-10-02]}
             }) ==
               {:error, "Girokonto bekommt schon die Umsätze eines anderen Bankkontos."}

      assert Enum.all?(
               BankSync.get_connection!(budget_scope(), ctx.connection.id).linked_accounts,
               &is_nil(&1.account_id)
             )
    end

    test "refuses a linked account without a start date", ctx do
      assert BankSync.assign_accounts(budget_scope(), ctx.connection, %{
               ctx.current.id => %{account_id: ctx.giro.id, start_date: nil}
             }) == {:error, "Girokonto braucht ein Datum, ab dem Abakus abruft."}
    end

    test "refuses an account that takes no entries", ctx do
      for account <- [
            account_fixture(fed_by: :shared_expenses),
            account_fixture(closed: true)
          ] do
        assert BankSync.assign_accounts(budget_scope(), ctx.connection, %{
                 ctx.current.id => %{account_id: account.id, start_date: ~D[2026-10-02]}
               }) == {:error, "Das gewählte Konto nimmt keine Bankumsätze."}
      end
    end

    test "keeps an account that no longer takes entries", ctx do
      assignment = %{account_id: ctx.giro.id, start_date: ~D[2026-10-02]}

      {:ok, _connection} =
        BankSync.assign_accounts(budget_scope(), ctx.connection, %{ctx.current.id => assignment})

      Repo.update!(Ecto.Changeset.change(ctx.giro, closed: true))

      assert {:ok, %{linked_accounts: [current, _savings]}} =
               BankSync.assign_accounts(budget_scope(), ctx.connection, %{
                 ctx.current.id => assignment
               })

      assert current.account_id == ctx.giro.id

      assert BankSync.assign_accounts(budget_scope(), ctx.connection, %{
               ctx.savings.id => %{assignment | account_id: ctx.giro.id}
             }) == {:error, "Das gewählte Konto nimmt keine Bankumsätze."}
    end
  end

  describe "assign_accounts/3 and the last fetch" do
    test "starts over at the start date only when the account or the date changes" do
      connection = connection_fixture()
      [current, _savings] = connection.linked_accounts
      giro = account_fixture()
      assignment = %{account_id: giro.id, start_date: ~D[2026-10-02]}

      {:ok, _connection} =
        BankSync.assign_accounts(budget_scope(), connection, %{current.id => assignment})

      fetched =
        Repo.update!(
          Ecto.Changeset.change(Repo.reload!(current),
            last_fetch_at: ~U[2026-10-20 06:00:00.000000Z]
          )
        )

      {:ok, _connection} =
        BankSync.assign_accounts(budget_scope(), connection, %{current.id => assignment})

      assert Repo.reload!(fetched).last_fetch_at == ~U[2026-10-20 06:00:00.000000Z]

      {:ok, _connection} =
        BankSync.assign_accounts(budget_scope(), connection, %{
          current.id => %{assignment | start_date: ~D[2026-09-01]}
        })

      assert Repo.reload!(fetched).last_fetch_at == nil
    end
  end

  describe "fetch/3" do
    setup do
      connection = connection_fixture()
      [current, savings] = connection.linked_accounts
      giro = account_fixture(name: "Girokonto")

      {:ok, connection} =
        BankSync.assign_accounts(budget_scope(), connection, %{
          current.id => %{account_id: giro.id, start_date: ~D[2026-09-15]}
        })

      FakeClient.put_transactions("uid-giro", [
        FakeClient.transaction(
          entry_reference: "E-1",
          date: ~D[2026-10-12],
          amount: -4200,
          creditor: "Stadtwerke",
          remittance: ["SVWZ+Abschlag Oktober"]
        ),
        FakeClient.transaction(
          status: :pending,
          transaction_id: "P-1",
          date: ~D[2026-10-19],
          amount: -640
        )
      ])

      FakeClient.put_balances("uid-giro", [
        %{type: :interim_booked, amount: 9900, date: ~D[2026-10-20]},
        %{type: :closing_booked, amount: 12_000, date: ~D[2026-10-19]}
      ])

      %{connection: connection, current: current, savings: savings, giro: giro}
    end

    test "imports the linked accounts' transactions from their start dates", ctx do
      assert {:ok, run} = BankSync.fetch(budget_scope(), ctx.connection)
      assert {run.trigger, run.new, run.matched, run.error} == {:manual, 2, 0, nil}

      assert FakeClient.fetches() == [
               {:transactions, "uid-giro", ~D[2026-09-15], nil},
               {:balances, "uid-giro", nil}
             ]

      assert [pending, transaction] = Ledger.list_transactions(budget_scope(), ctx.giro)
      assert %{amount: -640, cleared: :uncleared} = pending

      assert %{
               date: ~D[2026-10-12],
               amount: -4200,
               cleared: :cleared,
               approved: false,
               source: :bank,
               memo: "Abschlag Oktober"
             } = transaction

      assert transaction.payee.name == "Stadtwerke"

      assert %{source: :bank, external_id: "E-1"} =
               Repo.get_by!(TransactionOrigin, transaction_id: transaction.id)

      assert %{amount: 12_000, date: ~D[2026-10-19], source: :bank} =
               Ledger.latest_bank_balance(budget_scope(), ctx.giro)

      connection = BankSync.get_connection!(budget_scope(), ctx.connection.id)
      assert connection.last_sync_at == run.started_at
      assert connection.last_error == nil
      assert [^run] = connection.sync_runs
    end

    test "fetches again from 14 days before the last fetch and imports nothing twice", ctx do
      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)
      linked = Repo.get!(LinkedAccount, ctx.current.id)

      linked
      |> Ecto.Changeset.change(last_fetch_at: ~U[2026-10-20 10:00:00.000000Z])
      |> Repo.update!()

      assert {:ok, %{new: 0, matched: 0}} = BankSync.fetch(budget_scope(), ctx.connection)

      assert {:transactions, "uid-giro", ~D[2026-10-06], nil} in FakeClient.fetches()
      assert [_pending, _booked] = Ledger.list_transactions(budget_scope(), ctx.giro)
    end

    test "takes nothing dated before the start date, whatever the bank reports", ctx do
      FakeClient.put_transactions("uid-giro", fn ->
        [
          FakeClient.transaction(entry_reference: "E-0", date: ~D[2026-09-14], amount: -100),
          FakeClient.transaction(entry_reference: "E-1", date: ~D[2026-09-15], amount: -200)
        ]
      end)

      assert {:ok, %{new: 1}} = BankSync.fetch(budget_scope(), ctx.connection)
      assert [%{amount: -200}] = Ledger.list_transactions(budget_scope(), ctx.giro)
    end

    test "imports two alike transactions without bank ids once each", ctx do
      coffee = FakeClient.transaction(date: ~D[2026-10-14], amount: -350, creditor: "Café")
      FakeClient.put_transactions("uid-giro", [coffee, coffee])

      assert {:ok, %{new: 2}} = BankSync.fetch(budget_scope(), ctx.connection)
      assert {:ok, %{new: 0}} = BankSync.fetch(budget_scope(), ctx.connection)

      assert [%{amount: -350}, %{amount: -350}] =
               Ledger.list_transactions(budget_scope(), ctx.giro)
    end

    test "passes on the PSU data of a manual fetch, never of a scheduled one", ctx do
      psu = %{ip_address: "203.0.113.7", user_agent: "Firefox"}

      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection, psu: psu)
      {:ok, run} = BankSync.fetch(budget_scope(), ctx.connection, trigger: :scheduled, psu: psu)

      assert run.trigger == :scheduled

      assert FakeClient.fetches() == [
               {:transactions, "uid-giro", ~D[2026-09-15], psu},
               {:balances, "uid-giro", psu},
               {:transactions, "uid-giro", ~D[2026-10-06], nil},
               {:balances, "uid-giro", nil}
             ]
    end

    test "keeps a refused fetch's error until the next succeeds", ctx do
      {:ok, ok_run} = BankSync.fetch(budget_scope(), ctx.connection)
      FakeClient.fail_fetches(:rate_limited)

      assert BankSync.fetch(budget_scope(), ctx.connection) ==
               {:error,
                "Girokonto: Die Bank hat den Abruf abgelehnt: für heute waren es zu viele Abrufe."}

      connection = BankSync.get_connection!(budget_scope(), ctx.connection.id)
      assert connection.last_error =~ "zu viele Abrufe"
      assert connection.last_sync_at == ok_run.started_at
      assert [%{error: "Girokonto: Die Bank" <> _rest}, ^ok_run] = connection.sync_runs

      FakeClient.fail_fetches(nil)
      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)

      assert BankSync.get_connection!(budget_scope(), ctx.connection.id).last_error == nil
    end

    test "refuses an account that no longer takes entries", ctx do
      {:ok, _closed} = Ledger.update_account(budget_scope(), ctx.giro, %{closed: true})

      assert {:error, "Girokonto: Das Konto ist geschlossen" <> _rest} =
               BankSync.fetch(budget_scope(), ctx.connection)

      assert FakeClient.fetches() == []
    end

    test "fetches the other accounts when one fails and keeps every error", ctx do
      tagesgeld = account_fixture(name: "Tagesgeld")

      {:ok, connection} =
        BankSync.assign_accounts(budget_scope(), ctx.connection, %{
          ctx.savings.id => %{account_id: tagesgeld.id, start_date: ~D[2026-10-01]}
        })

      FakeClient.put_transactions("uid-savings", [
        FakeClient.transaction(entry_reference: "S-1", date: ~D[2026-10-05], amount: 1000)
      ])

      {:ok, _closed} = Ledger.update_account(budget_scope(), ctx.giro, %{closed: true})

      assert {:error, "Girokonto: Das Konto ist geschlossen" <> _rest = error} =
               BankSync.fetch(budget_scope(), connection)

      assert [%{amount: 1000}] = Ledger.list_transactions(budget_scope(), tagesgeld)

      connection = BankSync.get_connection!(budget_scope(), connection.id)
      assert [%{new: 1, matched: 0, error: ^error}] = connection.sync_runs
      assert connection.last_error == error
      assert connection.last_sync_at == nil

      {:ok, _reopened} =
        Ledger.update_account(budget_scope(), Repo.reload!(ctx.giro), %{closed: false})

      FakeClient.fail_fetches(:rate_limited)

      assert {:error, "Girokonto: " <> _rest = error} = BankSync.fetch(budget_scope(), connection)
      assert error =~ "zu viele Abrufe. Tagesgeld: Die Bank hat den Abruf abgelehnt"
    end

    test "keeps an unexpected failure as the run's error", ctx do
      tagesgeld = account_fixture(name: "Tagesgeld")

      {:ok, connection} =
        BankSync.assign_accounts(budget_scope(), ctx.connection, %{
          ctx.savings.id => %{account_id: tagesgeld.id, start_date: ~D[2026-10-01]}
        })

      FakeClient.put_transactions("uid-savings", fn -> raise "kaputt" end)

      assert capture_log(fn ->
               assert BankSync.fetch(budget_scope(), connection) ==
                        {:error, "Tagesgeld: Der Abruf ist unerwartet fehlgeschlagen."}
             end) =~ "kaputt"

      assert [%{new: 2, error: "Tagesgeld: Der Abruf ist unerwartet" <> _rest}] =
               BankSync.get_connection!(budget_scope(), connection.id).sync_runs
    end

    test "keeps no run of a fetch that was stopped", ctx do
      test = self()

      {:ok, connection} =
        BankSync.assign_accounts(budget_scope(), ctx.connection, %{
          ctx.savings.id => %{account_id: account_fixture().id, start_date: ~D[2026-10-01]}
        })

      FakeClient.put_transactions("uid-savings", fn ->
        send(test, {:fetching, self()})
        Process.sleep(:infinity)
      end)

      spawn(fn -> BankSync.fetch(budget_scope(), connection) end)
      assert_receive {:fetching, pid}
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert [_pending, _booked] = Ledger.list_transactions(budget_scope(), ctx.giro)
      assert BankSync.get_connection!(budget_scope(), connection.id).sync_runs == []
    end

    test "starts over at the start date an account gets while it is fetched", ctx do
      FakeClient.put_transactions("uid-giro", fn ->
        {:ok, _connection} =
          BankSync.assign_accounts(budget_scope(), ctx.connection, %{
            ctx.current.id => %{account_id: ctx.giro.id, start_date: ~D[2026-09-01]}
          })

        []
      end)

      assert {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)
      assert Repo.reload!(ctx.current).last_fetch_at == nil
    end

    test "says so when the connection is removed while it is fetched", ctx do
      FakeClient.put_transactions("uid-giro", fn ->
        {:ok, _connection} = BankSync.delete_connection(budget_scope(), ctx.connection)
        []
      end)

      assert BankSync.fetch(budget_scope(), ctx.connection) ==
               {:error, "Die Bankverbindung gibt es nicht mehr."}
    end

    test "runs one fetch per connection at a time", ctx do
      lock = {{BankSync, ctx.connection.id}, self()}
      true = :global.set_lock(lock, [node()], 0)

      assert Task.await(Task.async(fn -> BankSync.fetch(budget_scope(), ctx.connection) end)) ==
               {:error, "Der Abruf läuft schon."}

      :global.del_lock(lock, [node()])
      assert {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)
    end

    test "lists the last five runs, newest first", ctx do
      runs = for _fetch <- 1..6, do: elem(BankSync.fetch(budget_scope(), ctx.connection), 1)

      assert BankSync.get_connection!(budget_scope(), ctx.connection.id).sync_runs ==
               runs |> Enum.reverse() |> Enum.take(5)
    end
  end

  describe "fetch/3 with pending transactions" do
    setup do
      connection = connection_fixture()
      [current, _savings] = connection.linked_accounts
      giro = account_fixture(name: "Girokonto")

      {:ok, connection} =
        BankSync.assign_accounts(budget_scope(), connection, %{
          current.id => %{account_id: giro.id, start_date: ~D[2026-10-01]}
        })

      %{connection: connection, current: current, giro: giro}
    end

    defp report(transactions), do: FakeClient.put_transactions("uid-giro", transactions)

    defp pending(attrs),
      do: FakeClient.transaction(Keyword.merge([status: :pending, date: ~D[2026-10-07]], attrs))

    defp booked(attrs), do: FakeClient.transaction(Keyword.put_new(attrs, :date, ~D[2026-10-08]))

    defp register(giro),
      do: budget_scope() |> Ledger.list_transactions(giro) |> Enum.reverse()

    defp approve(transaction, attrs \\ %{}) do
      {:ok, approved} =
        Ledger.update_transaction(budget_scope(), transaction, Map.put(attrs, :approved, true))

      approved
    end

    test "imports a pending transaction once, as Vorgemerkt", ctx do
      report([pending(amount: -4200, creditor: "Stadtwerke")])

      assert {:ok, %{new: 1}} = BankSync.fetch(budget_scope(), ctx.connection)
      assert {:ok, %{new: 0}} = BankSync.fetch(budget_scope(), ctx.connection)

      assert [transaction] = register(ctx.giro)

      assert %{amount: -4200, cleared: :uncleared, approved: false, source: :bank} = transaction
      assert transaction.payee.name == "Stadtwerke"

      assert %{external_id: "pending:2026-10-07 -4200 stadtwerke"} =
               Repo.get_by!(TransactionOrigin, transaction_id: transaction.id)
    end

    test "replaces an unapproved pending transaction by the booked one", ctx do
      report([pending(transaction_id: "T-7", amount: -640, creditor: "Bäckerei Korn")])
      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)
      [vorgemerkt] = register(ctx.giro)

      report([booked(transaction_id: "T-7", amount: -640, creditor: "BAECKEREI KORN")])

      assert {:ok, %{new: 1, matched: 0}} = BankSync.fetch(budget_scope(), ctx.connection)

      assert Repo.reload!(vorgemerkt).deleted_at
      assert [gebucht] = register(ctx.giro)
      assert %{amount: -640, cleared: :cleared, approved: false} = gebucht
      assert gebucht.payee.name == "BAECKEREI KORN"
    end

    test "proposes the booked transaction as a match for an approved pending one", ctx do
      groceries = category_fixture(name: "Lebensmittel")
      report([pending(amount: -5837, creditor: "Frischmarkt")])
      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)
      vorgemerkt = ctx.giro |> register() |> hd() |> approve(%{category_id: groceries.id})

      report([booked(entry_reference: "E-8", amount: -5837, creditor: "FRISCHMARKT SAGT DANKE")])

      assert {:ok, %{new: 0, matched: 1}} = BankSync.fetch(budget_scope(), ctx.connection)
      assert [proposal] = Ledger.list_match_proposals(budget_scope(), ctx.giro)
      assert proposal.matched_transaction_id == vorgemerkt.id

      {:ok, _accepted} = Ledger.accept_match(budget_scope(), proposal)

      assert [%{id: id, cleared: :cleared, category_id: category_id}] = register(ctx.giro)
      assert {id, category_id} == {vorgemerkt.id, groceries.id}
    end

    test "proposes the booked transaction instead of its pending one while the bank reports both",
         ctx do
      manual = transaction_fixture(account_id: ctx.giro.id, date: ~D[2026-10-06], amount: -5837)
      vorgemerkt = pending(amount: -5837, creditor: "Frischmarkt")
      report([vorgemerkt])
      assert {:ok, %{new: 0, matched: 1}} = BankSync.fetch(budget_scope(), ctx.connection)

      report([vorgemerkt, booked(entry_reference: "E-8", amount: -5837, creditor: "Frischmarkt")])
      assert {:ok, %{new: 0, matched: 1}} = BankSync.fetch(budget_scope(), ctx.connection)
      assert [%{id: id}, %{cleared: :uncleared, approved: false}] = register(ctx.giro)
      assert id == manual.id

      report([booked(entry_reference: "E-8", amount: -5837, creditor: "Frischmarkt")])
      assert {:ok, %{new: 0, matched: 0}} = BankSync.fetch(budget_scope(), ctx.connection)

      assert [%{id: id}] = register(ctx.giro)
      assert id == manual.id
      assert [proposal] = Ledger.list_match_proposals(budget_scope(), ctx.giro)
      assert proposal.matched_transaction_id == manual.id

      {:ok, _accepted} = Ledger.accept_match(budget_scope(), proposal)
      assert [%{id: ^id, cleared: :cleared}] = register(ctx.giro)

      assert %{external_id: "E-8"} = Repo.get_by!(TransactionOrigin, transaction_id: id)
    end

    test "removes an unapproved pending transaction the bank no longer reports", ctx do
      report([pending(transaction_id: "T-9", amount: -15_000, creditor: "Hotel Kaution")])
      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)

      report([])
      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)

      assert register(ctx.giro) == []
    end

    test "keeps an approved pending transaction whose booking differs", ctx do
      report([pending(amount: -3000, creditor: "Restaurant")])
      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)
      ctx.giro |> register() |> hd() |> approve()

      report([booked(entry_reference: "E-10", amount: -3300, creditor: "Restaurant")])

      assert {:ok, %{new: 1, matched: 0}} = BankSync.fetch(budget_scope(), ctx.connection)

      assert [%{amount: -3000, cleared: :uncleared}, %{amount: -3300, cleared: :cleared}] =
               register(ctx.giro)
    end

    test "keeps a pending transaction whose booked version is dated up to the last reconcile",
         ctx do
      report([pending(transaction_id: "T-11", amount: -2500, creditor: "Tankstelle")])
      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)
      transaction_fixture(account_id: ctx.giro.id, date: ~D[2026-10-09], cleared: :reconciled)

      report([booked(transaction_id: "T-11", amount: -2500, creditor: "Tankstelle")])

      assert {:ok, %{new: 0, matched: 0}} = BankSync.fetch(budget_scope(), ctx.connection)
      assert [%{amount: -2500, cleared: :uncleared}, _reconciled] = register(ctx.giro)
    end

    test "keeps a pending transaction dated before the fetched window", ctx do
      report([pending(date: ~D[2026-10-02], amount: -990, creditor: "Kiosk")])
      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)

      LinkedAccount
      |> Repo.get!(ctx.current.id)
      |> Ecto.Changeset.change(last_fetch_at: ~U[2026-10-20 10:00:00.000000Z])
      |> Repo.update!()

      {:ok, _run} = BankSync.fetch(budget_scope(), ctx.connection)

      assert {:transactions, "uid-giro", ~D[2026-10-06], nil} in FakeClient.fetches()
      assert [%{amount: -990}] = register(ctx.giro)
    end
  end

  describe "fetch_all/1" do
    test "fetches each connection with a linked account on schedule" do
      unlinked = connection_fixture()
      FakeClient.put_session("code-1", %{FakeClient.session() | session_id: "session-2"})
      linked = connection_fixture()
      [current, _savings] = linked.linked_accounts

      {:ok, _connection} =
        BankSync.assign_accounts(budget_scope(), linked, %{
          current.id => %{account_id: account_fixture().id, start_date: ~D[2026-10-01]}
        })

      assert [{%{id: id}, {:ok, %{trigger: :scheduled}}}] = BankSync.fetch_all(budget_scope())
      assert id == linked.id
      assert BankSync.get_connection!(budget_scope(), unlinked.id).sync_runs == []
    end
  end

  describe "entries/1" do
    test "keeps the booked and pending transactions with a date and an amount" do
      booked = FakeClient.transaction(entry_reference: "E-1", date: ~D[2026-10-02], amount: -100)

      assert [
               %{external_id: "E-1", cleared: :cleared},
               %{external_id: "pending:E-1", cleared: :uncleared}
             ] =
               BankSync.entries([
                 booked,
                 %{booked | status: :pending},
                 %{booked | status: :other},
                 %{booked | date: nil},
                 %{booked | amount: nil}
               ])
    end

    test "takes the entry reference, else the transaction id, else a key as the external id" do
      booked =
        FakeClient.transaction(date: ~D[2026-10-02], amount: -640, creditor: "Bäckerei Korn")

      assert [
               %{external_id: "E-1"},
               %{external_id: "T-1"},
               %{external_id: key},
               %{external_id: pending_key}
             ] =
               BankSync.entries([
                 %{booked | entry_reference: "E-1", transaction_id: "T-1"},
                 %{booked | transaction_id: "T-1"},
                 booked,
                 %{booked | status: :pending}
               ])

      assert key == "2026-10-02 -640 bäckerei korn"
      assert pending_key == "pending:" <> key
    end

    test "numbers a key that repeats, but no bank id" do
      booked =
        FakeClient.transaction(date: ~D[2026-10-02], amount: -640, creditor: "Bäckerei Korn")

      assert [
               "2026-10-02 -640 bäckerei korn",
               "pending:2026-10-02 -640 bäckerei korn",
               "2026-10-02 -640 bäckerei korn 2",
               "E-1",
               "E-1",
               "pending:2026-10-02 -640 bäckerei korn 2",
               "2026-10-02 -640 bäckerei korn 3"
             ] ==
               [
                 booked,
                 %{booked | status: :pending},
                 booked,
                 %{booked | entry_reference: "E-1"},
                 %{booked | entry_reference: "E-1"},
                 %{booked | status: :pending},
                 booked
               ]
               |> BankSync.entries()
               |> Enum.map(& &1.external_id)
    end

    test "names the creditor of a debit, the debtor of a credit, else the first remittance line" do
      booked =
        FakeClient.transaction(
          entry_reference: "E-1",
          date: ~D[2026-10-02],
          creditor: "Stadtwerke",
          debtor: "Robert",
          remittance: ["EREF+123 SVWZ+Abschlag", "Oktober", "  "]
        )

      assert [
               %{payee_name: "Stadtwerke", memo: "123 Abschlag Oktober"},
               %{payee_name: "Robert"},
               %{payee_name: "123 Abschlag"},
               %{payee_name: "123 Abschlag"},
               %{payee_name: nil, memo: nil}
             ] =
               BankSync.entries([
                 %{booked | amount: -100},
                 %{booked | amount: 100},
                 %{booked | amount: -100, creditor: nil},
                 %{booked | amount: 0},
                 %{booked | amount: 100, debtor: nil, remittance: []}
               ])
    end
  end

  describe "bank_balance/1" do
    test "is the closing booked balance, else the interim booked one, dated today without a date" do
      closing = %{type: :closing_booked, amount: 100, date: ~D[2026-10-19]}
      interim = %{type: :interim_booked, amount: 200, date: nil}
      expected = %{type: :other, amount: 300, date: ~D[2026-10-20]}

      assert BankSync.bank_balance([interim, closing, expected]) ==
               %{amount: 100, date: ~D[2026-10-19]}

      assert BankSync.bank_balance([interim, expected]) == %{amount: 200, date: ~D[2026-10-20]}
      assert BankSync.bank_balance([expected]) == nil
    end
  end

  describe "failing?/1" do
    setup do
      connection = connection_fixture()
      [current, savings] = connection.linked_accounts

      {:ok, _connection} =
        BankSync.assign_accounts(budget_scope(), connection, %{
          current.id => %{account_id: account_fixture().id, start_date: ~D[2026-10-01]}
        })

      %{current: current, savings: savings}
    end

    test "is whether a connection has an error and no successful fetch for more than a day" do
      refute BankSync.failing?(Scope.system())

      failing = fn attrs ->
        Repo.update_all(Connection, set: attrs)
        BankSync.failing?(Scope.system())
      end

      two_days_ago = ~U[2026-10-18 10:00:00.000000Z]
      an_hour_ago = ~U[2026-10-20 09:00:00.000000Z]

      refute failing.(last_error: "kaputt", last_sync_at: an_hour_ago)
      assert failing.(last_error: "kaputt", last_sync_at: two_days_ago)
      refute failing.(last_error: nil, last_sync_at: two_days_ago)
      refute failing.(last_error: "kaputt", last_sync_at: nil)

      Repo.update_all(Connection, set: [inserted_at: two_days_ago])
      assert BankSync.failing?(Scope.system())
    end

    test "counts only connections that are fetched, and none without bank sync", ctx do
      Repo.update_all(Connection,
        set: [last_error: "kaputt", last_sync_at: ~U[2026-10-18 10:00:00.000000Z]]
      )

      assert BankSync.failing?(Scope.system())

      [connection] = BankSync.list_connections(budget_scope())

      {:ok, _connection} =
        BankSync.assign_accounts(budget_scope(), connection, %{
          ctx.current.id => %{account_id: nil},
          ctx.savings.id => %{account_id: nil}
        })

      refute BankSync.failing?(Scope.system())
      assert BankSync.fetch_all(budget_scope()) == []

      Repo.update_all(from(l in LinkedAccount, where: l.id == ^ctx.current.id),
        set: [account_id: account_fixture().id, start_date: ~D[2026-10-01]]
      )

      assert BankSync.failing?(Scope.system())
      stop_supervised!(FakeClient)
      refute BankSync.failing?(Scope.system())
    end
  end

  test "removes a connection with its accounts" do
    connection = connection_fixture()

    assert {:ok, _connection} = BankSync.delete_connection(budget_scope(), connection)
    assert BankSync.list_connections(budget_scope()) == []
    assert {:ok, _connection} = BankSync.delete_connection(budget_scope(), connection)
  end

  test "is the budget owner's alone" do
    connection = connection_fixture()
    account = account_fixture()
    other = Scope.for_user(Abakus.UsersFixtures.user_fixture())

    {:ok, %{auth: auth}} =
      BankSync.authorize(budget_scope(), %{name: "Musterbank", country: "DE"}, "https://x")

    for call <- [
          fn -> BankSync.banks(other, "DE") end,
          fn -> BankSync.authorize(other, %{name: "Musterbank", country: "DE"}, "https://x") end,
          fn -> BankSync.list_connections(other) end,
          fn -> BankSync.get_connection!(other, connection.id) end,
          fn -> BankSync.delete_connection(other, connection) end,
          fn -> BankSync.fetch(other, connection) end,
          fn -> BankSync.fetch_all(Scope.system()) end,
          fn -> BankSync.connect(other, auth, "code-1") end,
          fn -> BankSync.assign_accounts(other, connection, %{}) end,
          fn -> BankSync.start_date(other, account) end,
          fn -> BankSync.failing?(budget_scope()) end,
          fn -> BankSync.accounts(Scope.system()) end
        ] do
      assert_raise AccessError, call
    end
  end
end

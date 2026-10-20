defmodule Abakus.BankSyncTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.BankSyncFixtures

  alias Abakus.{BankSync, Repo}
  alias Abakus.BankSync.{AccessError, FakeClient}
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
          fn -> BankSync.connect(other, auth, "code-1") end,
          fn -> BankSync.assign_accounts(other, connection, %{}) end,
          fn -> BankSync.start_date(other, account) end,
          fn -> BankSync.accounts(Scope.system()) end
        ] do
      assert_raise AccessError, call
    end
  end
end

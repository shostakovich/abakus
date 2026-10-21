defmodule Abakus.Depot.BudgetLinkTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures, only: [budget_scope: 0]
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures

  alias Abakus.{Categories, DomainFixtures, FileImport, Ledger}
  alias Abakus.Depot.{AccountRoles, BudgetLink, CashSide, Portfolios}
  alias Abakus.Ledger.{Account, Transaction}

  @start ~D[2026-10-01]
  @day ~D[2026-10-02]

  setup do
    owner = user_scope_fixture()
    giro = DomainFixtures.account_fixture(name: "Giro")
    investieren = DomainFixtures.category_fixture(name: "Investieren")

    {:ok, portfolio} =
      Portfolios.create_portfolio(owner, %{name: "Langfristig", account_name: "Broker-Cash"})

    clearing = account_fixture(owner, %{name: "Giro-Verrechnung"})
    {:ok, clearing} = AccountRoles.set_role(owner, clearing, "budget_account:#{giro.id}")

    security = security_fixture(%{name: "Welt-ETF", quote_feed: :manual, symbol: nil})
    price_fixture(security, @start, price(100), :manual)

    broker_cash = Repo.get!(Portfolios.Account, portfolio.reference_account_id)

    %{
      owner: owner,
      giro: giro,
      investieren: investieren,
      portfolio: portfolio,
      tracking: Repo.get!(Account, Repo.reload!(portfolio).budget_account_id),
      clearing: clearing,
      broker_cash: broker_cash,
      broker_cash_account: ledger_account(broker_cash),
      security: security
    }
  end

  defp ledger_account(depot_account),
    do: Repo.get!(Account, Repo.reload!(depot_account).ledger_account_id)

  defp switch_on(c, start \\ @start) do
    {:ok, link} =
      BudgetLink.switch_on(c.owner, %{category_id: c.investieren.id, start_date: start})

    link
  end

  defp book(c, kind, attrs) do
    form =
      Map.merge(
        %{
          "kind" => kind,
          "date" => Date.to_iso8601(@day),
          "portfolio_id" => c.portfolio.id,
          "security_id" => c.security.id,
          "account_id" => c.clearing.id
        },
        attrs
      )

    {:ok, [transaction]} =
      Portfolios.book_transaction(c.owner, Portfolios.transaction_choices(c.owner), form)

    transaction
  end

  defp purchase(c, shares, attrs \\ %{}),
    do: book(c, "purchase", Map.merge(%{"shares" => "#{shares}", "price" => "100"}, attrs))

  defp register(account) do
    Repo.all(
      from t in Ledger.in_register(budget_scope()),
        where: t.account_id == ^account.id,
        order_by: t.id,
        preload: [:payee, :category]
    )
  end

  defp linked_transaction_ids,
    do:
      Repo.all(
        from t in Transaction,
          where: not is_nil(t.depot_transaction_id) and is_nil(t.deleted_at),
          select: t.id
      )

  describe "a purchase paid from a budget account" do
    test "is one linked outflow in the purchase category, unapproved, with the portfolio", c do
      switch_on(c)
      purchase(c, 9)

      assert [
               %Transaction{amount: -90_000, date: @day, approved: false, source: :depot} =
                 outflow
             ] =
               register(c.giro)

      assert outflow.category_id == c.investieren.id
      assert {outflow.payee.name, outflow.transfer_transaction_id} == {"Langfristig", nil}
      assert outflow.memo == "Kauf Welt-ETF"
      assert register(c.tracking) == []
    end

    test "an OFX line with its amount is proposed as the match of the linked outflow", c do
      switch_on(c, ~D[2026-09-01])
      purchase(c, "0,5837", %{"date" => "2026-09-14"})
      [outflow] = register(c.giro)
      assert outflow.amount == -5_837

      {:ok, [statement]} =
        FileImport.read(File.read!("test/fixtures/ofx/girokonto_2026-09.ofx"))

      preview = FileImport.preview(budget_scope(), statement, c.giro)

      assert Enum.any?(
               preview.rows,
               &match?(%{status: :matched, match: %{id: id}} when id == outflow.id, &1)
             )
    end
  end

  test "a purchase from the broker's cash touches the budget not at all", c do
    transaction_fixture(c.owner, ~D[2026-09-30],
      type: :deposit,
      account_id: c.broker_cash.id,
      amount: 100_000
    )

    switch_on(c)
    purchase(c, 9, %{"account_id" => c.broker_cash.id})

    assert register(c.giro) == []
    assert register(c.tracking) == []
    assert Ledger.balance(budget_scope(), c.broker_cash_account, @day) == 10_000
  end

  test "a dividend paid to a budget account is an inflow to Ready to Assign from the security",
       c do
    switch_on(c)
    purchase(c, 9)
    book(c, "dividend", %{"gross" => "42,17", "shares" => "9"})

    assert [_outflow, %Transaction{amount: 4_217, approved: false} = inflow] = register(c.giro)
    assert inflow.category_id == Categories.ready_to_assign!(budget_scope()).id
    assert inflow.payee.name == "Welt-ETF"
    assert inflow.transfer_transaction_id == nil
  end

  test "a sale paid to a budget account is an inflow to Ready to Assign with the portfolio", c do
    switch_on(c)
    purchase(c, 9)
    book(c, "sale", %{"shares" => "4", "price" => "100"})

    assert [_outflow, %Transaction{amount: 40_000} = inflow] = register(c.giro)
    assert inflow.category_id == Categories.ready_to_assign!(budget_scope()).id
    assert {inflow.payee.name, inflow.transfer_transaction_id} == {"Langfristig", nil}
  end

  test "money moved from a budget account to the broker's cash is a transfer, an outflow in the purchase category",
       c do
    switch_on(c)

    for {from, to, amount} <- [
          {c.clearing, c.broker_cash, 30_000},
          {c.broker_cash, c.clearing, 5_000}
        ] do
      transaction_fixture(c.owner, @day,
        type: :cash_transfer,
        account_id: from.id,
        other_account_id: to.id,
        amount: amount
      )
    end

    :ok = CashSide.sync(c.owner)

    assert [%Transaction{amount: -30_000} = out, %Transaction{amount: 5_000} = back] =
             register(c.giro)

    assert out.category_id == c.investieren.id
    assert back.category_id == Categories.ready_to_assign!(budget_scope()).id
    assert out.payee.transfer_account_id == c.broker_cash_account.id

    assert [%Transaction{amount: 30_000, cleared: :cleared, approved: true}, %Transaction{}] =
             register(c.broker_cash_account)

    assert Ledger.balance(budget_scope(), c.broker_cash_account, @day) == 25_000
  end

  test "a linked transaction the Ledger refuses books nothing in the Depot either", c do
    link = switch_on(c)
    member = user_scope_fixture()
    {:ok, group} = Categories.create_category_group(member, %{name: "Fremd"})

    {:ok, foreign} =
      Categories.create_category(member, %{name: "Fremd", category_group_id: group.id})

    Repo.update!(Ecto.Changeset.change(link, category_id: foreign.id))

    form = %{
      "kind" => "purchase",
      "date" => Date.to_iso8601(@day),
      "portfolio_id" => c.portfolio.id,
      "security_id" => c.security.id,
      "account_id" => c.clearing.id,
      "shares" => "1",
      "price" => "100"
    }

    assert {:error, "Die Buchung in Finanzen ließ sich nicht schreiben" <> _rest} =
             Portfolios.book_transaction(c.owner, Portfolios.transaction_choices(c.owner), form)

    assert Portfolios.list_transactions(c.owner) == []
    assert register(c.giro) == []
  end

  describe "the Depot leads" do
    test "amount, date and payee follow it, the register keeps category and approval", c do
      switch_on(c)
      purchase = purchase(c, 9)
      [outflow] = register(c.giro)
      other = DomainFixtures.category_fixture()

      {:ok, _} =
        Ledger.update_transaction(budget_scope(), outflow, %{
          category_id: other.id,
          approved: true,
          memo: "Mein Memo"
        })

      params =
        purchase
        |> Portfolios.transaction_form_params()
        |> Map.merge(%{"amount" => "950", "amount_set" => "true", "date" => "2026-10-03"})

      {:ok, _} =
        Portfolios.update_transaction(
          c.owner,
          Portfolios.transaction_choices(c.owner, purchase),
          purchase,
          params
        )

      assert [%Transaction{amount: -95_000, date: ~D[2026-10-03], approved: true} = changed] =
               register(c.giro)

      assert {changed.id, changed.category_id, changed.memo} ==
               {outflow.id, other.id, "Mein Memo"}
    end

    test "keeps its date when a bank line is matched to it", c do
      switch_on(c)
      purchase(c, 9)
      [outflow] = register(c.giro)

      {:ok, proposal} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.giro.id,
          date: ~D[2026-10-05],
          amount: outflow.amount,
          source: :file,
          matched_transaction_id: outflow.id
        })

      {:ok, _matched} = Ledger.accept_match(budget_scope(), proposal)
      :ok = CashSide.sync(c.owner)

      assert [%Transaction{date: @day, approved: true}] = register(c.giro)
    end

    test "the register cannot change what it leads", c do
      switch_on(c)
      purchase(c, 9)
      [outflow] = register(c.giro)

      assert {:error, changeset} =
               Ledger.update_transaction(budget_scope(), outflow, %{date: ~D[2026-10-05]})

      assert [date: {"folgt der Buchung im Depot", []}] = changeset.errors
    end

    test "deleting the Depot transaction deletes the linked one", c do
      switch_on(c)
      purchase = purchase(c, 9)

      {:ok, _} = Portfolios.delete_transaction(c.owner, purchase)

      assert register(c.giro) == []
      assert register(c.tracking) == []
      assert linked_transaction_ids() == []
    end

    test "deleting a cash transfer deletes its linked transaction", c do
      switch_on(c)

      transfer =
        transaction_fixture(c.owner, @day,
          type: :cash_transfer,
          account_id: c.clearing.id,
          other_account_id: c.broker_cash.id,
          amount: 30_000
        )

      :ok = CashSide.sync(c.owner)
      assert [%Transaction{amount: -30_000}] = register(c.giro)

      {:ok, _} = Portfolios.delete_transaction(c.owner, transfer)

      assert register(c.giro) == []
      assert register(c.broker_cash_account) == []
      assert linked_transaction_ids() == []
    end

    test "an account that stops being a budget account takes its linked transactions to a tracking account of its own",
         c do
      switch_on(c)
      purchase(c, 9)

      {:ok, _} = AccountRoles.set_role(c.owner, c.clearing, "none")

      assert register(c.giro) == []
      own = ledger_account(c.clearing)
      assert {own.name, own.kind} == {"Giro-Verrechnung", :tracking}
      assert [%Transaction{amount: -90_000, category_id: nil}] = register(own)
    end
  end

  describe "the start date" do
    test "keeps earlier Depot transactions in the Depot only, and links later ones on switching on",
         c do
      purchase(c, 1, %{"date" => "2026-09-15"})
      purchase(c, 2)

      switch_on(c)

      assert [%Transaction{amount: -20_000}] = register(c.giro)
    end

    test "nothing is linked while it is off", c do
      purchase(c, 9)

      assert register(c.giro) == []
      assert BudgetLink.get(c.owner) == nil
    end
  end

  describe "switching on" do
    test "only the budget owner can, once, with a regular category", c do
      member = user_scope_fixture()
      attrs = %{category_id: c.investieren.id, start_date: @start}

      assert {:error, :not_budget_owner} = BudgetLink.switch_on(member, attrs)

      internal = Categories.ready_to_assign!(budget_scope())

      assert {:error, %Ecto.Changeset{errors: [category_id: _]}} =
               BudgetLink.switch_on(c.owner, %{attrs | category_id: internal.id})

      switch_on(c)
      assert {:error, :linked} = BudgetLink.switch_on(c.owner, attrs)
    end

    test "changing the category changes the scope's own link", c do
      switch_on(c)
      other = DomainFixtures.category_fixture(name: "Sparen")

      assert {:ok, link} = BudgetLink.change_category(c.owner, other.id)
      assert link.category_id == other.id
      assert Repo.reload!(link).category_id == other.id
    end

    test "sees only the user's own budget", c do
      member = user_scope_fixture()
      {:ok, group} = Categories.create_category_group(member, %{name: "Eigenes"})

      {:ok, own} =
        Categories.create_category(member, %{name: "Investieren", category_group_id: group.id})

      link = switch_on(c)
      purchase(c, 2)
      assert [linked_id | _] = linked_transaction_ids()

      assert [{_group, [{"Investieren", id}]}] = BudgetLink.category_options(c.owner)
      assert id == c.investieren.id
      assert [{"Eigenes", [{"Investieren", own_id}]}] = BudgetLink.category_options(member)
      assert own_id == own.id
      assert {:error, %Ecto.Changeset{}} = BudgetLink.change_category(c.owner, own.id)
      assert {:error, :not_linked} = BudgetLink.change_category(member, own.id)

      linked = %Transaction{id: linked_id}
      assert {:depot_transaction, _id} = Ledger.led_by(budget_scope(), linked)
      assert_raise Ecto.NoResultsError, fn -> Ledger.led_by(member, linked) end

      :ok = BudgetLink.recategorize(member, c.investieren.id, own.id)
      assert Repo.reload!(link).category_id == c.investieren.id
    end

    test "deleting the purchase category moves the link to the category it goes into", c do
      link = switch_on(c)
      into = DomainFixtures.category_fixture()

      {:ok, _} = Categories.delete_category(budget_scope(), c.investieren, into)

      assert Repo.reload!(link).category_id == into.id
    end
  end
end

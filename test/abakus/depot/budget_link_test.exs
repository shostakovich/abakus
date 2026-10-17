defmodule Abakus.Depot.BudgetLinkTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures, only: [budget_scope: 0]
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures

  alias Abakus.{Categories, DomainFixtures, FileImport, Ledger}
  alias Abakus.Depot.{AccountRoles, BudgetFeed, BudgetLink, Portfolios}
  alias Abakus.Depot.BudgetLink.LinkedTransaction
  alias Abakus.Depot.Portfolios.Portfolio
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

    %{
      owner: owner,
      giro: giro,
      investieren: investieren,
      portfolio: portfolio,
      tracking: Repo.get!(Account, Repo.reload!(portfolio).budget_account_id),
      clearing: clearing,
      broker_cash: Repo.get!(Portfolios.Account, portfolio.reference_account_id),
      security: security
    }
  end

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

  defp linked_in(account), do: Enum.reject(register(account), &(&1.payee.name == "Wertänderung"))

  defp value_changes(account),
    do: Enum.filter(register(account), &(&1.payee.name == "Wertänderung"))

  describe "a purchase paid from a budget account" do
    test "is a linked outflow in the purchase category, unapproved, transferred to the portfolio's account",
         c do
      switch_on(c)
      purchase(c, 9)

      assert [
               %Transaction{amount: -90_000, date: @day, approved: false, source: :depot} =
                 outflow
             ] =
               register(c.giro)

      assert outflow.category_id == c.investieren.id
      assert outflow.payee.transfer_account_id == c.tracking.id
      assert outflow.memo == "Kauf Welt-ETF"

      assert [%Transaction{amount: 90_000, date: @day}] = register(c.tracking)
      assert Ledger.balance(budget_scope(), c.tracking, @day) == 90_000
    end

    test "leaves only the market movement to that night's value change", c do
      switch_on(c)
      purchase(c, 9)

      :ok = BudgetFeed.book_value_changes(@day)
      assert value_changes(c.tracking) == []

      price_fixture(c.security, ~D[2026-10-03], price(110), :manual)
      :ok = BudgetFeed.book_value_changes(~D[2026-10-03])

      assert [%Transaction{amount: 9_000}] = value_changes(c.tracking)
      assert [%Transaction{amount: 90_000}] = linked_in(c.tracking)
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
    assert linked_in(c.tracking) == []

    cash = AccountRoles.cash_account_ids(c.portfolio)
    assert Portfolios.value(c.owner, [c.portfolio.id], cash, @day) == 100_000
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

  test "a sale paid to a budget account is an inflow transferred from the portfolio's account",
       c do
    switch_on(c)
    purchase(c, 9)
    book(c, "sale", %{"shares" => "4", "price" => "100"})

    assert [_outflow, %Transaction{amount: 40_000} = inflow] = register(c.giro)
    assert inflow.category_id == Categories.ready_to_assign!(budget_scope()).id
    assert inflow.payee.transfer_account_id == c.tracking.id
    assert Ledger.balance(budget_scope(), c.tracking, @day) == 50_000
  end

  test "money moved from a budget account into a portfolio's cash is an outflow, and back an inflow",
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

    :ok = BudgetLink.sync(c.owner)

    assert [%Transaction{amount: -30_000} = out, %Transaction{amount: 5_000}] = register(c.giro)
    assert out.category_id == c.investieren.id
    assert Ledger.balance(budget_scope(), c.tracking, @day) == 25_000
  end

  test "dollars moved from a portfolio's cash to a budget account are an inflow of the euros received",
       c do
    usd = account_fixture(c.owner, %{name: "USD-Cash", currency: "USD"})
    {:ok, usd} = AccountRoles.set_role(c.owner, usd, "portfolio_cash:#{c.portfolio.id}")
    switch_on(c)

    received = %Portfolios.TransactionUnit{
      type: :gross_value,
      amount: 11_000,
      currency: "USD",
      fx_amount: 10_000,
      fx_currency: "EUR"
    }

    transaction_fixture(c.owner, @day,
      type: :cash_transfer,
      account_id: usd.id,
      other_account_id: c.clearing.id,
      amount: 11_000,
      currency: "USD",
      units: [received]
    )

    :ok = BudgetLink.sync(c.owner)

    assert [%Transaction{amount: 10_000, memo: "Entnahme"}] = register(c.giro)
  end

  test "a linked transaction the Ledger refuses books nothing in the Depot either", c do
    switch_on(c)
    Repo.update!(Ecto.Changeset.change(c.giro, kind: :tracking))

    form = %{
      "kind" => "purchase",
      "date" => Date.to_iso8601(@day),
      "portfolio_id" => c.portfolio.id,
      "security_id" => c.security.id,
      "account_id" => c.clearing.id,
      "shares" => "1",
      "price" => "100"
    }

    assert {:error, "Die Buchung im Budget ließ sich nicht schreiben" <> _rest} =
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

    test "keeps the bank's date after a match until the Depot changes the date", c do
      switch_on(c)
      purchase(c, 9)
      [outflow] = register(c.giro)
      {:ok, _} = Ledger.update_transaction(budget_scope(), outflow, %{date: ~D[2026-10-05]})

      :ok = BudgetLink.sync(c.owner)

      assert [%Transaction{date: ~D[2026-10-05]}] = register(c.giro)
    end

    test "deleting the Depot transaction deletes the linked one and its transfer", c do
      switch_on(c)
      purchase = purchase(c, 9)

      {:ok, _} = Portfolios.delete_transaction(c.owner, purchase)

      assert register(c.giro) == []
      assert register(c.tracking) == []
      assert Repo.aggregate(LinkedTransaction, :count) == 0
    end

    test "an account that stops being a budget account takes its linked transactions along", c do
      switch_on(c)
      purchase(c, 9)

      {:ok, _} = AccountRoles.set_role(c.owner, c.clearing, "none")

      assert register(c.giro) == []
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
      ids = Repo.all(from l in LinkedTransaction, select: l.transaction_id)
      assert ids != []

      assert [{_group, [{"Investieren", id}]}] = BudgetLink.category_options(c.owner)
      assert id == c.investieren.id
      assert [{"Eigenes", [{"Investieren", own_id}]}] = BudgetLink.category_options(member)
      assert own_id == own.id
      assert {:error, %Ecto.Changeset{}} = BudgetLink.change_category(c.owner, own.id)
      assert {:error, :not_linked} = BudgetLink.change_category(member, own.id)

      assert BudgetLink.linked_ids(c.owner, ids) == MapSet.new(ids)
      assert BudgetLink.linked_ids(member, ids) == MapSet.new()

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

  test "a portfolio without its account yet gets a plain outflow named after it", c do
    portfolio = portfolio_fixture(c.owner, %{name: "Kinder"})
    assert %Portfolio{budget_account_id: nil} = portfolio
    switch_on(c)

    purchase(c, 1, %{"portfolio_id" => portfolio.id})

    assert [%Transaction{amount: -10_000} = outflow] = register(c.giro)
    assert outflow.payee.name == "Kinder"
  end
end

defmodule Abakus.Depot.BookingTest do
  use Abakus.DataCase

  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures

  alias Abakus.Depot.{Portfolios, PPImport, Valuation}
  alias Abakus.Depot.Portfolios.{Receipt, Transaction, TransactionForm}
  alias Abakus.Depot.Valuation.Market
  alias Abakus.LocalTime

  @day ~D[2026-10-01]

  setup do
    scope = user_scope_fixture()
    account = account_fixture(scope, name: "Verrechnungskonto")
    portfolio = portfolio_fixture(scope, reference_account_id: account.id)
    security = security_fixture()

    %{
      scope: scope,
      account: account,
      portfolio: portfolio,
      security: security,
      choices: Portfolios.transaction_choices(scope)
    }
  end

  defp form(ctx, kind, attrs) do
    Map.merge(
      %{
        "kind" => kind,
        "date" => Date.to_iso8601(@day),
        "portfolio_id" => ctx.portfolio.id,
        "security_id" => ctx.security.id,
        "account_id" => ctx.account.id
      },
      attrs
    )
  end

  defp book(ctx, kind, attrs, receipt \\ nil),
    do: Portfolios.book_transaction(ctx.scope, ctx.choices, form(ctx, kind, attrs), receipt)

  defp booked(transaction) do
    transaction = Repo.preload(transaction, :units, force: true)

    transaction
    |> Map.take([:type, :portfolio_id, :account_id, :security_id, :shares, :amount, :currency])
    |> Map.put(:units, Enum.map(transaction.units, &{&1.type, &1.amount}))
  end

  # Holdings, account balances and invested capital at the end of the day.
  defp figures(ctx) do
    transactions = Portfolios.list_transactions(ctx.scope)
    market = Market.new([ctx.security], [], [])

    [%{invested_capital: invested}] =
      Valuation.history(transactions, Portfolios.list_accounts(ctx.scope), market, [@day])

    %{
      holdings: for(h <- Valuation.holdings(transactions, @day), do: {h.portfolio_id, h.shares}),
      balances: Valuation.balances(transactions, @day),
      invested_capital: invested
    }
  end

  describe "the amount" do
    test "follows shares and price with fees", ctx do
      changeset =
        Portfolios.change_transaction_form(
          ctx.scope,
          ctx.choices,
          form(ctx, "purchase", %{"shares" => "10", "price" => "100,0000", "fees" => "1,00"})
        )

      assert Decimal.equal?(get_field(changeset, :amount), "1001.00")
      assert get_field(changeset, :expected_amount) == nil
    end

    test "warns when overwritten far from shares × price, and still books", ctx do
      attrs = %{
        "shares" => "31,0700",
        "price" => "12,0699",
        "amount" => "375,02",
        "amount_set" => "true"
      }

      changeset =
        Portfolios.change_transaction_form(ctx.scope, ctx.choices, form(ctx, "purchase", attrs))

      assert Decimal.equal?(get_field(changeset, :expected_amount), "375.01")
      assert changeset.valid?

      assert {:ok, [transaction]} = book(ctx, "purchase", attrs)
      assert transaction.amount == 37_502
    end

    test "overwritten within the rounding of a four-decimal price does not warn", ctx do
      attrs = %{
        "shares" => "31,07",
        "price" => "12,0699",
        "amount" => "375,01",
        "amount_set" => "true"
      }

      changeset =
        Portfolios.change_transaction_form(ctx.scope, ctx.choices, form(ctx, "purchase", attrs))

      assert get_field(changeset, :expected_amount) == nil
    end
  end

  describe "book_transaction/4 books as the PP import would" do
    test "a purchase from an account", ctx do
      attrs = %{"shares" => "10", "price" => "100", "fees" => "4,50", "taxes" => "1"}
      assert {:ok, [purchase]} = book(ctx, "purchase", attrs)

      assert booked(purchase) == %{
               type: :buy,
               portfolio_id: ctx.portfolio.id,
               account_id: ctx.account.id,
               security_id: ctx.security.id,
               shares: shares(10),
               amount: money(1_005.50),
               currency: "EUR",
               units: [fee: 450, tax: 100]
             }

      assert %Transaction{source: :manual, date_time: ~N[2026-10-01 00:00:00]} = purchase

      assert figures(ctx) == %{
               holdings: [{ctx.portfolio.id, shares(10)}],
               balances: %{ctx.account.id => -money(1_005.50)},
               invested_capital: 0
             }
    end

    test "a purchase without an account as an inbound delivery", ctx do
      attrs = %{"shares" => "10", "price" => "100", "account_id" => ""}
      assert {:ok, [delivery]} = book(ctx, "purchase", attrs)

      assert %{type: :inbound_delivery, account_id: nil, amount: 100_000} = booked(delivery)

      assert figures(ctx) == %{
               holdings: [{ctx.portfolio.id, shares(10)}],
               balances: %{},
               invested_capital: money(1_000)
             }
    end

    test "a sale into an account, and without one as an outbound delivery", ctx do
      {:ok, _} = book(ctx, "purchase", %{"shares" => "10", "price" => "100", "account_id" => ""})
      attrs = %{"shares" => "4", "price" => "105", "fees" => "4,50", "taxes" => "3,20"}
      assert {:ok, [sale]} = book(ctx, "sale", attrs)

      assert booked(sale) == %{
               type: :sell,
               portfolio_id: ctx.portfolio.id,
               account_id: ctx.account.id,
               security_id: ctx.security.id,
               shares: shares(4),
               amount: money(412.30),
               currency: "EUR",
               units: [fee: 450, tax: 320]
             }

      attrs = %{"shares" => "1", "price" => "105", "account_id" => ""}
      assert {:ok, [delivery]} = book(ctx, "sale", attrs)
      assert %{type: :outbound_delivery, account_id: nil, amount: 10_500} = booked(delivery)

      assert figures(ctx) == %{
               holdings: [{ctx.portfolio.id, shares(5)}],
               balances: %{ctx.account.id => money(412.30)},
               invested_capital: money(1_000 - 105)
             }
    end

    test "a dividend on the account, without a portfolio side", ctx do
      attrs = %{"shares" => "40", "gross" => "100", "taxes" => "18,50"}
      assert {:ok, [dividend]} = book(ctx, "dividend", attrs)

      assert booked(dividend) == %{
               type: :dividend,
               portfolio_id: nil,
               account_id: ctx.account.id,
               security_id: ctx.security.id,
               shares: shares(40),
               amount: money(81.50),
               currency: "EUR",
               units: [tax: 1_850]
             }

      assert figures(ctx).balances == %{ctx.account.id => money(81.50)}
    end

    test "a deposit and a removal", ctx do
      assert {:ok, [deposit]} = book(ctx, "deposit", %{"amount" => "1.000,00"})
      assert {:ok, [removal]} = book(ctx, "removal", %{"amount" => "250"})

      assert %{type: :deposit, portfolio_id: nil, security_id: nil, amount: 100_000, units: []} =
               booked(deposit)

      assert %{type: :removal, account_id: account_id, amount: 25_000} = booked(removal)
      assert account_id == ctx.account.id

      assert figures(ctx) == %{
               holdings: [],
               balances: %{ctx.account.id => money(750)},
               invested_capital: money(750)
             }
    end
  end

  test "a dividend removed at once books the dividend and a removal of its amount", ctx do
    attrs = %{"gross" => "100,00", "taxes" => "18,50", "remove_at_once" => "true"}
    assert {:ok, [dividend, removal]} = book(ctx, "dividend", attrs)

    assert %{type: :dividend, amount: 8_150} = booked(dividend)

    assert %{type: :removal, account_id: account_id, security_id: nil, amount: 8_150, units: []} =
             booked(removal)

    assert account_id == ctx.account.id
    assert removal.date_time == dividend.date_time
    assert removal.id != dividend.id
    assert figures(ctx).balances == %{ctx.account.id => 0}
  end

  describe "checks" do
    test "no sale beyond the holding on its day", ctx do
      {:ok, _} = book(ctx, "purchase", %{"shares" => "5", "price" => "100"})

      later = %{"date" => "2026-10-02", "shares" => "1", "price" => "100"}
      {:ok, _} = book(ctx, "purchase", later)

      assert {:error, changeset} = book(ctx, "sale", %{"shares" => "6", "price" => "100"})
      assert errors_on(changeset).shares == ["übersteigt den Bestand von 5 Stück"]

      assert {:ok, _} = book(ctx, "sale", %{"shares" => "5", "price" => "100"})
    end

    test "no sale before a later one beyond what stays", ctx do
      {:ok, _} = book(ctx, "purchase", %{"shares" => "5", "price" => "100"})
      {:ok, _} = book(ctx, "sale", %{"date" => "2026-10-03", "shares" => "4", "price" => "100"})

      backdated = %{"date" => "2026-10-02", "shares" => "2", "price" => "100"}
      assert {:error, changeset} = book(ctx, "sale", backdated)
      assert errors_on(changeset).shares == ["übersteigt den Bestand von 1 Stück"]

      assert {:ok, _} = book(ctx, "sale", %{backdated | "shares" => "1"})
    end

    test "required fields per type", ctx do
      empty = %{"date" => "2026-10-01", "portfolio_id" => "", "account_id" => ""}

      {:error, purchase} =
        Portfolios.book_transaction(ctx.scope, ctx.choices, Map.put(empty, "kind", "purchase"))

      assert sorted_keys(errors_on(purchase)) == [
               :amount,
               :portfolio_id,
               :price,
               :security_id,
               :shares
             ]

      {:error, dividend} =
        Portfolios.book_transaction(ctx.scope, ctx.choices, Map.put(empty, "kind", "dividend"))

      assert sorted_keys(errors_on(dividend)) == [:account_id, :amount, :gross, :security_id]

      {:error, deposit} =
        Portfolios.book_transaction(ctx.scope, ctx.choices, Map.put(empty, "kind", "deposit"))

      assert sorted_keys(errors_on(deposit)) == [:account_id, :amount]
    end

    test "no date in the future", ctx do
      tomorrow = LocalTime.today() |> Date.add(1) |> Date.to_iso8601()
      assert {:error, changeset} = book(ctx, "deposit", %{"amount" => "1", "date" => tomorrow})
      assert errors_on(changeset).date == ["darf nicht in der Zukunft liegen"]
    end

    test "only the user's own portfolios and accounts", ctx do
      other = user_scope_fixture()
      foreign = account_fixture(other)

      assert {:error, changeset} =
               book(ctx, "deposit", %{"amount" => "1", "account_id" => foreign.id})

      assert errors_on(changeset).account_id == ["ist ungültig"]

      foreign_portfolio = portfolio_fixture(other)
      purchase = %{"shares" => "1", "price" => "1", "portfolio_id" => foreign_portfolio.id}
      assert {:error, changeset} = book(ctx, "purchase", purchase)
      assert errors_on(changeset).portfolio_id == ["ist ungültig"]
    end

    test "only accounts in euros", ctx do
      dollars = account_fixture(ctx.scope, name: "Dollarkonto", currency: "USD")
      choices = Portfolios.transaction_choices(ctx.scope)
      refute dollars in choices.accounts

      assert {:error, changeset} =
               Portfolios.book_transaction(
                 ctx.scope,
                 choices,
                 form(ctx, "deposit", %{"amount" => "1", "account_id" => dollars.id})
               )

      assert errors_on(changeset).account_id == ["ist ungültig"]
    end

    test "amounts in whole cents", ctx do
      assert {:error, changeset} = book(ctx, "deposit", %{"amount" => "1,005"})
      assert errors_on(changeset).amount == ["hat höchstens 2 Nachkommastellen"]
    end

    test "no absurdly large numbers", ctx do
      huge = "1e30"

      assert {:error, purchase} =
               book(ctx, "purchase", %{"shares" => huge, "price" => huge, "fees" => huge})

      assert %{shares: [_], price: [_], fees: [_], amount: ["must be less than 1000000000"]} =
               errors_on(purchase)

      assert {:error, dividend} = book(ctx, "dividend", %{"gross" => huge, "taxes" => huge})
      assert %{gross: [_], taxes: [_]} = errors_on(dividend)

      assert {:error, deposit} = book(ctx, "deposit", %{"amount" => huge})
      assert errors_on(deposit).amount == ["must be less than 1000000000"]
      assert Portfolios.list_transactions(ctx.scope) == []
    end
  end

  defp sorted_keys(map), do: map |> Map.keys() |> Enum.sort()

  describe "receipts" do
    @pdf "%PDF-1.4\nein Beleg\n%%EOF\n"

    setup do
      path = Path.join(System.tmp_dir!(), "receipt-#{System.unique_integer([:positive])}.pdf")
      File.write!(path, @pdf)
      on_exit(fn -> File.rm(path) end)
      %{path: path}
    end

    test "are stored once per file and attached to the transaction", ctx do
      assert {:ok, [first]} = book(ctx, "deposit", %{"amount" => "1"}, {ctx.path, "a.pdf"})
      assert {:ok, [second]} = book(ctx, "deposit", %{"amount" => "2"}, {ctx.path, "b.pdf"})

      assert first.receipt_id == second.receipt_id
      receipt = Repo.get!(Receipt, first.receipt_id)
      assert %{filename: "a.pdf", byte_size: 25, user_id: user_id} = receipt
      assert user_id == ctx.scope.user.id
      assert receipt.sha256 == Base.encode16(:crypto.hash(:sha256, @pdf), case: :lower)
      assert File.read!(Portfolios.receipt_file(receipt)) == @pdf
    end

    test "attach to the dividend, not to its removal", ctx do
      attrs = %{"gross" => "10", "remove_at_once" => "true"}
      assert {:ok, [dividend, removal]} = book(ctx, "dividend", attrs, {ctx.path, "d.pdf"})
      assert dividend.receipt_id
      assert removal.receipt_id == nil
    end

    test "leave no file behind when booking fails", ctx do
      Repo.delete!(ctx.security)
      sha256 = Base.encode16(:crypto.hash(:sha256, @pdf), case: :lower)

      assert_raise Ecto.ConstraintError, fn ->
        book(ctx, "dividend", %{"gross" => "10"}, {ctx.path, "d.pdf"})
      end

      refute Repo.exists?(Receipt)
      refute File.exists?(Portfolios.receipt_file(sha256))

      refute sha256
             |> Portfolios.receipt_file()
             |> Path.dirname()
             |> File.ls!()
             |> Enum.any?(&(&1 =~ sha256))
    end

    test "must be PDFs", ctx do
      File.write!(ctx.path, "kein PDF")

      assert {:error, changeset} =
               book(ctx, "deposit", %{"amount" => "1"}, {ctx.path, "x.pdf"})

      assert errors_on(changeset).receipt == ["ist keine PDF-Datei"]
      assert Portfolios.list_transactions(ctx.scope) == []
    end
  end

  test "a PP re-import keeps manually booked transactions", ctx do
    {:ok, _} = PPImport.run(ctx.scope, "test/fixtures/depot/pp/sample.portfolio")
    {:ok, [deposit]} = book(ctx, "deposit", %{"amount" => "100"})

    {:ok, _} = PPImport.run(ctx.scope, "test/fixtures/depot/pp/sample.portfolio")

    assert Repo.get(Transaction, deposit.id)
  end

  describe "editing and deleting" do
    @pdf "%PDF-1.4\nein Beleg\n%%EOF\n"

    defp receipt_path(content) do
      path = Path.join(System.tmp_dir!(), "receipt-#{System.unique_integer([:positive])}.pdf")
      File.write!(path, content)
      on_exit(fn -> File.rm(path) end)
      path
    end

    defp edit(ctx, transaction, kind, attrs, receipt \\ nil) do
      transaction = Portfolios.get_transaction(ctx.scope, transaction.id)

      Portfolios.update_transaction(
        ctx.scope,
        ctx.choices,
        transaction,
        form(ctx, kind, attrs),
        receipt
      )
    end

    test "the form shows a booked transaction as it was entered", ctx do
      attrs = %{"shares" => "31,07", "price" => "12,0699", "fees" => "1", "taxes" => "0,5"}
      {:ok, [purchase]} = book(ctx, "purchase", attrs)

      params = Portfolios.get_transaction(ctx.scope, purchase.id) |> TransactionForm.params_of()

      assert params == %{
               "kind" => "purchase",
               "date" => "2026-10-01",
               "portfolio_id" => to_string(ctx.portfolio.id),
               "account_id" => to_string(ctx.account.id),
               "security_id" => to_string(ctx.security.id),
               "shares" => "31,07",
               # Not stored: 375,01 € gross over 31,07 shares.
               "price" => "12,0698",
               "fees" => "1,00",
               "taxes" => "0,50",
               "amount" => "376,51",
               "amount_set" => "false"
             }

      {:ok, [overwritten]} =
        book(ctx, "sale", %{
          "shares" => "1",
          "price" => "10",
          "amount" => "9,99",
          "amount_set" => "true"
        })

      assert %{"price" => "9,99", "amount" => "9,99", "amount_set" => "false"} =
               Portfolios.get_transaction(ctx.scope, overwritten.id)
               |> TransactionForm.params_of()

      {:ok, [dividend]} = book(ctx, "dividend", %{"gross" => "100", "taxes" => "18,5"})

      assert %{"kind" => "dividend", "gross" => "100,00", "amount" => "81,50"} =
               Portfolios.get_transaction(ctx.scope, dividend.id) |> TransactionForm.params_of()
    end

    test "editing a manual transaction updates the figures", ctx do
      {:ok, [purchase]} =
        book(ctx, "purchase", %{"shares" => "10", "price" => "100", "fees" => "1"})

      assert {:ok, updated} =
               edit(ctx, purchase, "purchase", %{
                 "shares" => "12",
                 "price" => "100",
                 "account_id" => ""
               })

      assert updated.id == purchase.id

      assert %{type: :inbound_delivery, shares: 1_200_000_000, amount: 120_000, units: []} =
               booked(updated)

      assert figures(ctx) == %{
               holdings: [{ctx.portfolio.id, shares(12)}],
               balances: %{},
               invested_capital: money(1_200)
             }
    end

    test "a sale being edited does not count against its own holding", ctx do
      {:ok, _} = book(ctx, "purchase", %{"shares" => "5", "price" => "100"})
      {:ok, [sale]} = book(ctx, "sale", %{"shares" => "5", "price" => "100"})

      assert {:ok, _} = edit(ctx, sale, "sale", %{"shares" => "5", "price" => "110"})
      assert {:error, changeset} = edit(ctx, sale, "sale", %{"shares" => "6", "price" => "110"})
      assert errors_on(changeset).shares == ["übersteigt den Bestand von 5 Stück"]
    end

    test "a transaction keeps its retired portfolio and account", ctx do
      {:ok, [purchase]} = book(ctx, "purchase", %{"shares" => "10", "price" => "100"})
      Repo.update!(Ecto.Changeset.change(ctx.portfolio, retired: true))
      Repo.update!(Ecto.Changeset.change(ctx.account, retired: true))
      assert %{portfolios: [], accounts: []} = Portfolios.transaction_choices(ctx.scope)

      purchase = Portfolios.get_transaction(ctx.scope, purchase.id)
      choices = Portfolios.transaction_choices(ctx.scope, purchase)
      assert [ctx.portfolio.id] == Enum.map(choices.portfolios, & &1.id)
      assert [ctx.account.id] == Enum.map(choices.accounts, & &1.id)

      params = Map.put(TransactionForm.params_of(purchase), "shares", "12")
      {:ok, updated} = Portfolios.update_transaction(ctx.scope, choices, purchase, params)

      assert %{type: :buy, portfolio_id: portfolio_id, account_id: account_id} = updated
      assert {portfolio_id, account_id} == {ctx.portfolio.id, ctx.account.id}
    end

    test "a purchase a later sale needs cannot shrink, move or go", ctx do
      {:ok, [purchase]} = book(ctx, "purchase", %{"shares" => "5", "price" => "100"})

      {:ok, [sale]} =
        book(ctx, "sale", %{"date" => "2026-10-03", "shares" => "4", "price" => "100"})

      other = portfolio_fixture(ctx.scope, name: "Anderes Depot")
      choices = Portfolios.transaction_choices(ctx.scope)
      negative = ["würde den Bestand später unter null bringen"]

      for attrs <- [
            %{"shares" => "3"},
            %{"date" => "2026-10-04"},
            %{"portfolio_id" => other.id},
            %{"kind" => "deposit", "amount" => "1"}
          ] do
        params = Map.merge(form(ctx, "purchase", %{"shares" => "5", "price" => "100"}), attrs)
        loaded = Portfolios.get_transaction(ctx.scope, purchase.id)

        assert {:error, changeset} =
                 Portfolios.update_transaction(ctx.scope, choices, loaded, params)

        assert negative in Map.values(errors_on(changeset))
      end

      assert {:error, :holding} = Portfolios.delete_transaction(ctx.scope, purchase)
      assert {:ok, _} = edit(ctx, purchase, "purchase", %{"shares" => "4", "price" => "100"})

      assert {:ok, _} =
               edit(ctx, purchase, "purchase", %{
                 "date" => "2026-10-03",
                 "shares" => "4",
                 "price" => "100"
               })

      assert {:ok, _} = Portfolios.delete_transaction(ctx.scope, sale)
      assert {:ok, _} = Portfolios.delete_transaction(ctx.scope, purchase)
    end

    test "imported and other users' transactions are read-only", ctx do
      {:ok, _} = PPImport.run(ctx.scope, "test/fixtures/depot/pp/sample.portfolio")
      imported = Repo.one!(from t in Transaction, where: t.type == :deposit, limit: 1)

      assert {:error, :read_only} = edit(ctx, imported, "deposit", %{"amount" => "1"})
      assert {:error, :read_only} = Portfolios.delete_transaction(ctx.scope, imported)

      {:ok, [own]} = book(ctx, "deposit", %{"amount" => "1"})
      other = user_scope_fixture()
      assert {:error, :read_only} = Portfolios.delete_transaction(other, own)

      other_account = account_fixture(other)

      assert {:error, :read_only} =
               Portfolios.update_transaction(
                 other,
                 Portfolios.transaction_choices(other),
                 own,
                 %{
                   "kind" => "deposit",
                   "date" => "2026-10-01",
                   "amount" => "2",
                   "account_id" => other_account.id
                 }
               )

      assert %{amount: 100, account_id: account_id} = Repo.get!(Transaction, own.id)
      assert account_id == ctx.account.id
      assert Portfolios.get_transaction(other, own.id) == nil
    end

    test "a transaction deleted meanwhile is gone", ctx do
      {:ok, [deposit]} = book(ctx, "deposit", %{"amount" => "1"})
      loaded = Portfolios.get_transaction(ctx.scope, deposit.id)

      assert {:ok, _} = Portfolios.delete_transaction(ctx.scope, deposit)
      assert Portfolios.get_transaction(ctx.scope, deposit.id) == nil
      assert {:ok, _} = Portfolios.delete_transaction(ctx.scope, deposit)

      assert {:error, :gone} =
               Portfolios.update_transaction(
                 ctx.scope,
                 ctx.choices,
                 loaded,
                 form(ctx, "deposit", %{"amount" => "2"})
               )

      assert Portfolios.list_transactions(ctx.scope) == []
    end

    test "deleting removes the receipt file once no transaction uses it", ctx do
      path = receipt_path(@pdf)
      {:ok, [first]} = book(ctx, "deposit", %{"amount" => "1"}, {path, "a.pdf"})
      {:ok, [second]} = book(ctx, "deposit", %{"amount" => "2"}, {path, "a.pdf"})
      file = Portfolios.receipt_file(Repo.get!(Receipt, first.receipt_id))

      assert {:ok, _} = Portfolios.delete_transaction(ctx.scope, first)
      refute Repo.get(Transaction, first.id)
      assert File.exists?(file)

      assert {:ok, _} = Portfolios.delete_transaction(ctx.scope, second)
      refute Repo.get(Receipt, second.receipt_id)
      refute File.exists?(file)
    end

    test "a receipt file another user's receipt needs stays", ctx do
      path = receipt_path(@pdf)
      {:ok, [own]} = book(ctx, "deposit", %{"amount" => "1"}, {path, "a.pdf"})

      other = user_scope_fixture()
      other_account = account_fixture(other)

      {:ok, _} =
        Portfolios.book_transaction(
          other,
          Portfolios.transaction_choices(other),
          %{
            "kind" => "deposit",
            "date" => "2026-10-01",
            "amount" => "1",
            "account_id" => other_account.id
          },
          {path, "b.pdf"}
        )

      assert {:ok, _} = Portfolios.delete_transaction(ctx.scope, own)

      assert File.exists?(
               Portfolios.receipt_file(Base.encode16(:crypto.hash(:sha256, @pdf), case: :lower))
             )
    end

    test "a new receipt replaces the old one, whose file goes", ctx do
      old = "%PDF-1.4\nalt\n%%EOF\n"
      {:ok, [deposit]} = book(ctx, "deposit", %{"amount" => "1"}, {receipt_path(old), "alt.pdf"})
      old_file = Portfolios.receipt_file(Repo.get!(Receipt, deposit.receipt_id))

      {:ok, kept} = edit(ctx, deposit, "deposit", %{"amount" => "2"})
      assert kept.receipt_id == deposit.receipt_id

      {:ok, updated} =
        edit(ctx, deposit, "deposit", %{"amount" => "2"}, {receipt_path(@pdf), "neu.pdf"})

      assert updated.receipt.filename == "neu.pdf"
      refute File.exists?(old_file)
      assert File.exists?(Portfolios.receipt_file(updated.receipt))
    end
  end

  describe "transactions_by_month/2" do
    test "groups by month, newest first, filtered by kind", ctx do
      {:ok, [deposit]} = book(ctx, "deposit", %{"amount" => "100", "date" => "2026-09-30"})
      {:ok, [purchase]} = book(ctx, "purchase", %{"shares" => "1", "price" => "50"})
      {:ok, [dividend]} = book(ctx, "dividend", %{"gross" => "1"})

      assert [{~D[2026-10-01], [first, second]}, {~D[2026-09-01], [third]}] =
               Portfolios.transactions_by_month(ctx.scope)

      assert Enum.map([first, second, third], & &1.id) == [dividend.id, purchase.id, deposit.id]
      assert first.security.name == ctx.security.name

      ids = fn filter ->
        for {_month, transactions} <- Portfolios.transactions_by_month(ctx.scope, filter),
            transaction <- transactions,
            do: transaction.id
      end

      assert ids.(:trades) == [purchase.id]
      assert ids.(:earnings) == [dividend.id]
      assert ids.(:account) == [deposit.id]
      assert Portfolios.transactions_by_month(user_scope_fixture()) == []
    end

    test "gives a portfolio's transactions with those of its cash and its reference account",
         ctx do
      cash = account_fixture(ctx.scope, name: "Cash", cash_of_portfolio_id: ctx.portfolio.id)
      other = account_fixture(ctx.scope, name: "Andere")

      [on_reference, on_cash, _other] =
        for account <- [ctx.account, cash, other],
            do:
              transaction_fixture(ctx.scope, @day,
                type: :deposit,
                account_id: account.id,
                amount: 100
              )

      ids =
        for {_month, transactions} <-
              Portfolios.transactions_by_month(ctx.scope, nil, ctx.portfolio),
            transaction <- transactions,
            do: transaction.id

      assert Enum.sort(ids) == Enum.sort([on_reference.id, on_cash.id])
    end
  end
end

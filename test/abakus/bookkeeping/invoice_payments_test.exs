defmodule Abakus.Bookkeeping.InvoicePaymentsTest do
  use Abakus.DataCase

  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures

  alias Abakus.{Bookkeeping, Categories, Ledger, UsersFixtures}
  alias Abakus.Bookkeeping.InvoicePayments
  alias Abakus.Users.Scope

  @total 99_068

  setup do
    scope = budget_scope()
    business = account_fixture(name: "Kontist", kind: :tracking)
    private = account_fixture(name: "Girokonto")
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [business.id])
    sender_fixture(scope)
    customer = customer_fixture(scope)

    %{
      scope: scope,
      business: business,
      private: private,
      customer: customer,
      invoice: invoice_fixture(scope, customer)
    }
  end

  defp incoming(account, attrs \\ []),
    do:
      transaction_fixture(
        Enum.into(attrs, %{account_id: account.id, amount: @total, date: ~D[2027-01-20]})
      )

  defp proposed_ids(scope, invoice),
    do:
      scope
      |> InvoicePayments.proposals([invoice])
      |> Map.get(invoice.id, [])
      |> Enum.map(& &1.id)

  defp paid_by(scope, invoice) do
    with %{id: id} <- InvoicePayments.payments(scope, [invoice])[invoice.id], do: id
  end

  describe "proposals/2" do
    test "are the business accounts' incoming transactions of the total from the invoice's date on",
         c do
      later = incoming(c.business, date: ~D[2027-02-01])
      same_day = incoming(c.business, date: ~D[2027-01-15])
      _before = incoming(c.business, date: ~D[2027-01-14])
      _private = incoming(c.private)
      _other_amount = incoming(c.business, amount: @total - 1)
      _outgoing = incoming(c.business, amount: -@total)
      deleted = incoming(c.business)
      {:ok, _deleted} = Ledger.delete_transaction(c.scope, deleted)

      {:ok, _transfer} =
        Ledger.create_transaction(c.scope, %{
          account_id: c.business.id,
          date: ~D[2027-01-20],
          amount: @total,
          payee_id: c.private.transfer_payee.id,
          counterpart_category_id: Categories.ready_to_assign!(c.scope).id
        })

      assert proposed_ids(c.scope, c.invoice) == [same_day.id, later.id]

      assert [%{payee: _payee} | _rest] =
               InvoicePayments.proposals(c.scope, [c.invoice])[c.invoice.id]
    end

    test "leave out a transaction that pays another invoice", c do
      other = invoice_fixture(c.scope, c.customer)
      payment = incoming(c.business)
      assert proposed_ids(c.scope, other) == [payment.id]

      {:ok, _payment} = InvoicePayments.confirm(c.scope, c.invoice, payment.id)

      assert proposed_ids(c.scope, other) == []
      assert InvoicePayments.proposals(c.scope, [c.invoice]) == %{}
    end

    test "are the user's own", c do
      incoming(c.business)
      other = Scope.for_user(UsersFixtures.user_fixture())

      assert InvoicePayments.proposals(other, [c.invoice]) == %{}
    end
  end

  describe "confirm/3" do
    test "marks the invoice paid by the transaction", c do
      payment = incoming(c.business)
      assert paid_by(c.scope, c.invoice) == nil

      assert {:ok, _payment} = InvoicePayments.confirm(c.scope, c.invoice, payment.id)

      assert paid_by(c.scope, c.invoice) == payment.id

      assert InvoicePayments.payments(c.scope, [c.invoice])[c.invoice.id].payee_id ==
               payment.payee_id
    end

    test "refuses a transaction that is no proposal", c do
      wrong = incoming(c.business, amount: 100)
      other = Scope.for_user(UsersFixtures.user_fixture())

      assert InvoicePayments.confirm(c.scope, c.invoice, wrong.id) == {:error, :not_found}
      assert InvoicePayments.confirm(c.scope, c.invoice, "x") == {:error, :not_found}

      assert InvoicePayments.confirm(other, c.invoice, incoming(c.business).id) ==
               {:error, :not_found}

      assert paid_by(c.scope, c.invoice) == nil
    end

    test "refuses a second payment", c do
      {:ok, _payment} = InvoicePayments.confirm(c.scope, c.invoice, incoming(c.business).id)
      second = incoming(c.business)

      assert InvoicePayments.confirm(c.scope, c.invoice, second.id) == {:error, :paid}
    end

    test "takes a new payment once the confirmed one left the register", c do
      first = incoming(c.business)
      {:ok, _payment} = InvoicePayments.confirm(c.scope, c.invoice, first.id)
      {:ok, _deleted} = Ledger.delete_transaction(c.scope, first)
      assert paid_by(c.scope, c.invoice) == nil

      second = incoming(c.business)
      assert {:ok, _payment} = InvoicePayments.confirm(c.scope, c.invoice, second.id)
      assert paid_by(c.scope, c.invoice) == second.id
    end
  end

  test "release/2 opens the invoice again", c do
    payment = incoming(c.business)
    {:ok, _payment} = InvoicePayments.confirm(c.scope, c.invoice, payment.id)

    assert :ok = InvoicePayments.release(c.scope, c.invoice)
    assert paid_by(c.scope, c.invoice) == nil
    assert proposed_ids(c.scope, c.invoice) == [payment.id]

    other = Scope.for_user(UsersFixtures.user_fixture())
    {:ok, _payment} = InvoicePayments.confirm(c.scope, c.invoice, payment.id)
    assert :ok = InvoicePayments.release(other, c.invoice)
    assert paid_by(c.scope, c.invoice) == payment.id
  end

  test "a transaction that pays an invoice needs no receipt in the inbox", c do
    payment = incoming(c.business)
    assert [{%{id: id}, [:category, :receipt]}] = Bookkeeping.inbox(c.scope)
    assert id == payment.id

    {:ok, _payment} = InvoicePayments.confirm(c.scope, c.invoice, payment.id)

    assert [{%{id: ^id}, [:category]}] = Bookkeeping.inbox(c.scope)
  end
end

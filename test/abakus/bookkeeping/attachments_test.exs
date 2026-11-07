defmodule Abakus.Bookkeeping.AttachmentsTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Bookkeeping, FakePaperless, Ledger, Paperless, UsersFixtures}
  alias Abakus.Bookkeeping.Attachments
  alias Abakus.Users.Scope

  @url "http://paperless.test"

  setup do
    scope = budget_scope()
    business = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [business.id])
    {:ok, _connection} = Paperless.update_connection(scope, %{"url" => @url, "token" => "t"})
    %{scope: scope, business: business}
  end

  defp serve(documents), do: FakePaperless.serve(%{@url => %{token: "t", documents: documents}})

  defp document(id, content, created, attrs \\ []),
    do: FakePaperless.fixture(id, [], [content: content, created: created] ++ attrs)

  defp transaction(account, attrs \\ []),
    do: transaction_fixture(Enum.into(attrs, %{account_id: account.id}))

  defp split(account, amounts) do
    {:ok, split} =
      Ledger.create_transaction(budget_scope(), %{
        account_id: account.id,
        date: ~D[2026-10-09],
        amount: Enum.sum(amounts),
        subtransactions: Enum.map(amounts, &%{amount: &1})
      })

    Bookkeeping.get_transaction(budget_scope(), split.id)
  end

  defp without_receipt(scope),
    do: for({t, missing} <- Bookkeeping.inbox(scope), :receipt in missing, do: t.id)

  defp proposed(scope, transaction) do
    {:ok, documents} = Attachments.proposals(scope, transaction)
    Enum.map(documents, & &1.id)
  end

  test "the inbox keeps a business transaction until it has a receipt or needs none", c do
    serve([document(1, "Rechnung", ~D[2026-10-09])])
    fee = transaction(c.business, amount: -990)
    hosting = transaction(c.business)

    assert Enum.sort(without_receipt(c.scope)) == Enum.sort([hosting.id, fee.id])

    assert {:ok, _attachment} = Attachments.attach(c.scope, hosting, nil, 1)
    assert :ok = Attachments.waive(c.scope, fee, true)
    assert without_receipt(c.scope) == []

    assert :ok = Attachments.waive(c.scope, fee, false)
    assert without_receipt(c.scope) == [fee.id]
  end

  test "a receipt of the whole split counts for its parts, else each part needs its own", c do
    serve([document(1, "Beleg", ~D[2026-10-09]), document(2, "Beleg", ~D[2026-10-09])])
    split = split(c.business, [-1_000, -500])
    [first, second] = split.subtransactions

    {:ok, _attachment} = Attachments.attach(c.scope, split, first.id, 1)
    assert without_receipt(c.scope) == [split.id]

    {:ok, _attachment} = Attachments.attach(c.scope, split, second.id, 2)
    assert without_receipt(c.scope) == []

    other = split(c.business, [-300, -200])
    {:ok, _attachment} = Attachments.attach(c.scope, other, nil, 1)
    refute other.id in without_receipt(c.scope)
  end

  test "lists the receipts by side, and only those of current sides", c do
    serve([document(1, "Beleg", ~D[2026-10-09], title: "Rechnung Mai"), document(2, "x", nil)])
    split = split(c.business, [-1_000, -500])
    [first, second] = split.subtransactions
    {:ok, whole} = Attachments.attach(c.scope, split, nil, 1)
    {:ok, part} = Attachments.attach(c.scope, split, first.id, 2)
    {:ok, ^part} = Attachments.attach(c.scope, split, first.id, 2)

    split_id = split.id
    first_id = first.id
    part_id = part.id

    assert %{
             {^split_id, nil} => [%{title: "Rechnung Mai"}],
             {^split_id, ^first_id} => [%{id: ^part_id}]
           } = Attachments.list(c.scope, [split])

    {:ok, _changed} =
      Ledger.update_transaction(c.scope, split, %{
        subtransactions: [%{id: second.id, amount: -500}, %{amount: -1_000}]
      })

    changed = Bookkeeping.get_transaction(c.scope, split.id)
    assert Map.keys(Attachments.list(c.scope, [changed])) == [{split.id, nil}]

    assert :ok = Attachments.detach(c.scope, whole.id)
    assert Attachments.list(c.scope, [changed]) == %{}
  end

  test "attaches only to the user's own transaction in the register, on a side it has", c do
    serve([document(1, "Beleg", ~D[2026-10-09])])
    hosting = transaction(c.business)
    other = Scope.for_user(UsersFixtures.user_fixture())
    {:ok, _connection} = Paperless.update_connection(other, %{"url" => @url, "token" => "t"})

    assert Attachments.attach(other, hosting, nil, 1) == {:error, :not_found}
    assert Attachments.attach(c.scope, hosting, Ecto.UUID.generate(), 1) == {:error, :side}
    assert Attachments.attach(c.scope, hosting, nil, 9) == {:error, {:http_status, 404}}

    {:ok, _transaction} = Ledger.delete_transaction(c.scope, hosting)
    assert Attachments.attach(c.scope, hosting, nil, 1) == {:error, :not_found}
  end

  test "takes no receipts for a transfer", c do
    serve([document(1, "Beleg", ~D[2026-10-09])])
    private = account_fixture(name: "Girokonto")

    {:ok, transfer} =
      Ledger.create_transaction(c.scope, %{
        account_id: c.business.id,
        date: ~D[2026-10-02],
        amount: -50_000,
        payee_id: private.transfer_payee.id,
        counterpart_category_id: Abakus.Categories.ready_to_assign!(c.scope).id
      })

    assert Attachments.attach(c.scope, transfer, nil, 1) == {:error, :side}
  end

  test "proposes unattached documents with the amount from a month before to a week after, closest first",
       c do
    serve([
      document(1, "Summe 1.234,56 EUR", ~D[2026-10-01]),
      document(2, "Total 1,234.56 USD", ~D[2026-10-09]),
      document(3, "Betrag 1234,56", ~D[2026-09-08]),
      document(4, "Betrag 1.234,56", ~D[2026-09-07]),
      document(5, "Betrag 1.234,56", ~D[2026-10-17]),
      document(6, "Betrag 1.234,57", ~D[2026-10-09]),
      document(7, "Betrag 1.234,56", ~D[2026-10-10])
    ])

    hosting = transaction(c.business, amount: -123_456)
    other = transaction(c.business)
    {:ok, _attachment} = Attachments.attach(c.scope, other, nil, 7)

    assert proposed(c.scope, hosting) == [2, 1, 3]
    assert proposed(c.scope, transaction(c.business, amount: 0)) == []
  end

  test "proposes nothing without Paperless", c do
    {:ok, _none} = Paperless.disconnect(c.scope)

    assert Attachments.proposals(c.scope, transaction(c.business)) == {:error, :not_connected}

    assert Attachments.attach(c.scope, transaction(c.business), nil, 1) ==
             {:error, :not_connected}
  end

  test "uploads a file to Paperless and attaches it, the document there for a file it has", c do
    serve([document(1, "Beleg", ~D[2026-10-09], pdf: "%PDF-1 known")])
    hosting = transaction(c.business)

    assert {:ok, %{paperless_id: 2, title: "Rechnung Mai"}} =
             Attachments.upload(c.scope, hosting, nil, "%PDF-1 new", "Rechnung Mai.pdf")

    assert {:ok, %{paperless_id: 1}} =
             Attachments.upload(c.scope, hosting, nil, "%PDF-1 known", "scan.pdf")

    assert [2, 1] =
             for(a <- Attachments.list(c.scope, [hosting])[{hosting.id, nil}], do: a.paperless_id)
  end

  test "tells an upload Paperless did not take", c do
    FakePaperless.serve(%{@url => %{token: "t", documents: [], uploads_fail: true}})

    assert Attachments.upload(c.scope, transaction(c.business), nil, "%PDF-1", "a.pdf") ==
             {:error, :not_consumed}
  end

  test "writes amounts as receipts do" do
    assert Attachments.notations(-123_456) == ["1.234,56", "1234,56", "1,234.56", "1234.56"]
    assert Attachments.notations(1_990) == ["19,90", "19.90"]
  end
end

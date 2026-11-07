defmodule Abakus.Bookkeeping.LexofficeImportTest do
  use Abakus.DataCase

  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures
  import Abakus.Owned, only: [owned: 2]

  alias Abakus.{FakePaperless, Paperless, Repo, UsersFixtures}
  alias Abakus.Users.Scope

  alias Abakus.Bookkeeping

  alias Abakus.Bookkeeping.{
    Attachment,
    Customer,
    FakeLexoffice,
    Filing,
    Filings,
    FixedAssets,
    Invoice,
    InvoicePayments,
    Invoices,
    LexofficeImport,
    LexofficeReceipt,
    LexofficeReceipts,
    TaxLine
  }

  @url "http://paperless.test"
  @key "lexoffice-key"

  setup do
    scope = budget_scope()
    {:ok, _connection} = Paperless.update_connection(scope, %{"url" => @url, "token" => "t"})
    FakePaperless.serve(%{@url => %{token: "t", documents: []}})
    FakeLexoffice.serve(@key)
    %{scope: scope}
  end

  defp run(scope, key \\ @key, opts \\ []), do: LexofficeImport.run(scope, fn -> key end, opts)

  defp fixture_json(path),
    do: JSON.decode!(File.read!("test/fixtures/bookkeeping/lexoffice/#{path}.json"))

  defp invoice(scope, number),
    do: Enum.find(Invoices.list_invoices(scope), &(&1.number == number))

  defp snapshot(scope) do
    %{
      customers: Enum.map(Invoices.list_customers(scope), &Map.drop(&1, [:__meta__])),
      invoices: Enum.map(Invoices.list_invoices(scope), &Map.drop(&1, [:__meta__])),
      receipts: rows(LexofficeReceipt),
      attachments: rows(Attachment),
      tax_lines: rows(TaxLine),
      filings: rows(Filing),
      documents: FakePaperless.documents(@url)
    }
  end

  defp rows(schema),
    do: Repo.all(from r in schema, order_by: r.id) |> Enum.map(&Map.drop(&1, [:__meta__]))

  defp kontist(scope) do
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    kontist
  end

  defp paid(account, date, amount),
    do: transaction_fixture(%{account_id: account.id, date: date, amount: amount})

  defp business_transactions(scope) do
    kontist = kontist(scope)

    %{
      office: [paid(kontist, ~D[2024-05-02], -1990), paid(kontist, ~D[2024-05-02], -1990)],
      internet: paid(kontist, ~D[2025-03-03], -11_900),
      software: paid(kontist, ~D[2025-10-28], -3195),
      desk: paid(kontist, ~D[2025-06-10], -142_800),
      search: paid(kontist, ~D[2025-12-24], -449)
    }
  end

  defp receipt(scope, number),
    do: Repo.one!(from r in owned(LexofficeReceipt, scope), where: r.number == ^number)

  defp attachments(transaction),
    do:
      Repo.all(
        from a in Attachment,
          where: a.transaction_id == ^transaction.id,
          order_by: a.title,
          select: a.title
      )

  defp tax_line(scope, transaction) do
    lines = Bookkeeping.tax_lines(scope, [Bookkeeping.get_transaction(scope, transaction.id)])
    line = lines[{transaction.id, nil}]
    line && {line.category, line.vat}
  end

  test "the import against recorded responses creates customers and invoices, and a second run changes nothing",
       %{scope: scope} do
    assert {:ok, result} = run(scope)
    assert result.customers == 3
    assert result.invoices == 4
    assert result.skipped == [{"2025110", "Rechnung mit mehreren Steuersätzen"}]
    assert result.locked == []

    assert Enum.map(Invoices.list_customers(scope), & &1.name) ==
             ["Erika Beispiel", "Esempio Digitale S.r.l.", "Jonas Käufer", "Muster & Söhne GmbH"]

    assert Enum.map(Invoices.list_invoices(scope), & &1.number) ==
             ["2026125", "2026124", "2024102", "2020041"]

    before = snapshot(scope)
    requests = length(FakeLexoffice.requests())

    assert {:ok, %{customers: 0, invoices: 0, receipts: 0, skipped: skipped}} = run(scope)
    assert skipped == result.skipped
    assert snapshot(scope) == before

    assert Enum.drop(FakeLexoffice.requests(), requests) ==
             [
               "contacts",
               "voucherlist",
               "voucherlist-1",
               "invoices/bbbbbbbb-0000-4000-8000-000000000005"
             ]
  end

  test "the import against recorded responses creates tax lines and receipts, puts an ambiguous receipt on the review list, and a second run changes nothing",
       %{scope: scope} do
    t = business_transactions(scope)

    assert {:ok, result} = run(scope)
    assert {result.receipts, result.matched, result.review} == {6, 4, 2}

    assert attachments(t.internet) == ["Beleg NT-88172"]
    assert tax_line(scope, t.internet) == {"internet", :rate_19}
    assert attachments(t.desk) == ["Beleg RE-55120", "Beleg RE-55120 (2)"]
    assert tax_line(scope, t.desk) == {"office_equipment", :rate_19}
    assert attachments(t.search) == ["Beleg SD-2025-12"]
    assert tax_line(scope, t.search) == {"licenses", :rate_0}
    assert attachments(t.software) == ["Beleg SW-2025-1028"]
    assert tax_line(scope, t.software) == nil

    software = receipt(scope, "SW-2025-1028")
    assert software.contact == "Softwarehaus Süd GmbH"
    assert software.total == -3195

    assert Enum.map(software.items, &{&1.category, &1.vat, &1.amount, &1.net}) ==
             [{"bank_fees", :rate_19, -589, -495}, {"licenses", :rate_19, -2606, -2190}]

    document = Enum.find(FakePaperless.documents(@url), &(&1.title == "Beleg SW-2025-1028"))
    assert document.pdf =~ "Lexoffice Beleg SW-2025-1028"
    assert software.paperless_ids == [document.id]

    refute Repo.exists?(from r in LexofficeReceipt, where: r.number == "BN-2025-0001")

    before = snapshot(scope)
    assert {:ok, %{receipts: 0, matched: 0, review: 2}} = run(scope)
    assert snapshot(scope) == before
  end

  test "an imported receipt without a clear payment waits for review", %{scope: scope} do
    %{office: [first, second]} = business_transactions(scope)
    {:ok, _result} = run(scope)

    assert [{refund, []}, {office, proposals}] = LexofficeReceipts.review(scope)
    assert {office.number, office.date, office.total} == {"BN-2024-0512", ~D[2024-05-02], -1990}
    assert Enum.sort(Enum.map(proposals, & &1.id)) == Enum.sort([first.id, second.id])
    assert attachments(first) == []
    assert attachments(second) == []
    assert {refund.number, refund.total} == {"UStVA-2025-Q4", 3273}
  end

  test "a receipt on the review list is attached to one of its proposals or dismissed", %{
    scope: scope
  } do
    %{office: [first, second]} = business_transactions(scope)
    {:ok, _result} = run(scope)
    office = receipt(scope, "BN-2024-0512")

    assert {:ok, _receipt} = LexofficeReceipts.attach(scope, office, first.id)
    assert attachments(first) == ["Beleg BN-2024-0512"]
    assert tax_line(scope, first) == {"office_supplies", :rate_19}
    assert LexofficeReceipts.attach(scope, office, second.id) == {:error, :not_found}

    refund = receipt(scope, "UStVA-2025-Q4")
    assert LexofficeReceipts.attach(scope, refund, second.id) == {:error, :not_found}
    assert LexofficeReceipts.dismiss(scope, refund) == :ok
    assert LexofficeReceipts.review(scope) == []
    assert LexofficeReceipts.review_count(scope) == 0
  end

  test "a receipt whose transaction left the register waits for review again", %{scope: scope} do
    t = business_transactions(scope)
    {:ok, _result} = run(scope)
    {:ok, _deleted} = Abakus.Ledger.delete_transaction(scope, t.internet)

    assert LexofficeReceipts.review_count(scope) == 3

    assert {_receipt, []} =
             Enum.find(LexofficeReceipts.review(scope), &(elem(&1, 0).number == "NT-88172"))

    internet = paid(%{id: t.internet.account_id}, ~D[2025-03-03], -11_900)
    assert LexofficeReceipts.match(scope) == 1
    assert attachments(internet) == ["Beleg NT-88172"]
  end

  test "a receipt in an Anlagevermögen category is proposed as a fixed asset", %{scope: scope} do
    business_transactions(scope)
    {:ok, _result} = run(scope)

    assert [desk] = LexofficeReceipts.asset_proposals(scope)
    asset = LexofficeReceipts.proposed_asset(desk)

    assert {asset.name, asset.purchased_on, asset.net} ==
             {"Büromarkt Nord GmbH", ~D[2025-06-06], 120_000}

    assert {:ok, recorded} =
             LexofficeReceipts.create_asset(scope, desk, %{
               "name" => "Schreibtisch",
               "purchased_on" => "2025-06-06",
               "net" => "1.200,00",
               "useful_life" => "13"
             })

    assert [recorded.id] == Enum.map(FixedAssets.list(scope), & &1.id)
    assert LexofficeReceipts.asset_proposals(scope) == []

    assert LexofficeReceipts.create_asset(scope, desk, %{
             "name" => "Schreibtisch",
             "purchased_on" => "2025-06-06",
             "net" => "1.200,00",
             "useful_life" => "13"
           }) == {:error, :not_proposed}

    assert [recorded.id] == Enum.map(FixedAssets.list(scope), & &1.id)
  end

  test "a dismissed proposal of a fixed asset is not proposed again", %{scope: scope} do
    {:ok, _result} = run(scope)
    [desk] = LexofficeReceipts.asset_proposals(scope)

    assert LexofficeReceipts.dismiss_asset(scope, desk) == :ok
    assert LexofficeReceipts.asset_proposals(scope) == []
    assert {:ok, %{receipts: 0}} = run(scope)
    assert LexofficeReceipts.asset_proposals(scope) == []
  end

  describe "the returns filed" do
    setup do
      Application.put_env(:abakus, :today, ~D[2026-11-07])
      on_exit(fn -> Application.delete_env(:abakus, :today) end)
    end

    test "are locked from the first year from Lexoffice on, the quarters up to the last Voranmeldung and the years up to the last year filed",
         %{scope: scope} do
      t = business_transactions(scope)

      assert {:ok, %{locked: locked}} =
               run(scope, @key, quarter_filed: {2026, 2}, year_filed: 2024)

      assert Enum.sort(locked) ==
               Enum.sort(
                 for(y <- 2020..2024, period <- [{:vat_year, y}, {:euer, y}], do: period) ++
                   for(y <- 2020..2026, q <- 1..4, {y, q} <= {2026, 2}, do: {:vat_quarter, y, q})
               )

      for period <- [
            {:vat_quarter, 2026, 2},
            {:vat_quarter, 2025, 4},
            {:vat_year, 2024},
            {:euer, 2020}
          ] do
        assert %{filed_elsewhere: true} = Filings.sent(scope, period)
      end

      for period <- [{:vat_quarter, 2026, 3}, {:vat_year, 2025}, {:euer, 2025}],
          do: assert(Filings.sent(scope, period) == nil)

      assert Filings.filed_elsewhere_through(scope, :vat_quarter) == {:vat_quarter, 2026, 2}
      assert Filings.filed_elsewhere_through(scope, :euer) == {:euer, 2024}

      for period <- [{:vat_year, 2024}, {:vat_quarter, 2026, 2}] do
        assert Filings.send_return(scope, period, "4711") ==
                 {:error, "Zeitraum ist festgeschrieben"}
      end

      office = receipt(scope, "BN-2024-0512")
      [first, _second] = t.office
      assert {:ok, _receipt} = LexofficeReceipts.attach(scope, office, first.id)
      assert attachments(first) == ["Beleg BN-2024-0512"]
      assert tax_line(scope, first) == nil

      assert Bookkeeping.save_tax_lines(scope, Bookkeeping.get_transaction(scope, first.id), %{
               "transaction" => %{"category" => "office_supplies", "vat" => "19"}
             }) == {:error, :locked}

      before = snapshot(scope)

      assert {:ok, %{locked: ^locked}} =
               run(scope, @key, quarter_filed: {2026, 2}, year_filed: 2024)

      assert snapshot(scope) == before
    end

    test "lock a year filed with its quarters", %{scope: scope} do
      assert {:ok, %{locked: locked}} = run(scope, @key, quarter_filed: nil, year_filed: 2020)

      assert Enum.sort(locked) ==
               Enum.sort([
                 {:vat_year, 2020},
                 {:euer, 2020} | for(q <- 1..4, do: {:vat_quarter, 2020, q})
               ])
    end

    test "leave the asset register open", %{scope: scope} do
      {:ok, _result} = run(scope, @key, quarter_filed: {2026, 3}, year_filed: 2025)
      [desk] = LexofficeReceipts.asset_proposals(scope)

      assert {:ok, asset} =
               LexofficeReceipts.create_asset(scope, desk, %{
                 "name" => "Schreibtisch",
                 "purchased_on" => "2025-06-06",
                 "net" => "1.200,00",
                 "useful_life" => "13"
               })

      assert {:ok, _asset} =
               FixedAssets.record_disposal(scope, asset, %{
                 "kind" => "withdrawal",
                 "date" => "2025-12-01",
                 "amount" => "500",
                 "vat" => "19"
               })
    end

    test "lock no period that is not over, nor any without one filed", %{scope: scope} do
      assert {:ok, %{locked: []}} = run(scope)

      assert {:ok, %{locked: locked}} =
               run(scope, @key, quarter_filed: {2026, 4}, year_filed: 2026)

      assert {:vat_quarter, 2026, 3} in locked
      assert {:euer, 2025} in locked

      for period <- [{:vat_quarter, 2026, 4}, {:vat_year, 2026}, {:euer, 2026}] do
        refute period in locked
        assert Filings.sent(scope, period) == nil
      end
    end
  end

  test "an imported invoice keeps Lexoffice's numbers, period and VAT and its original PDF in Paperless",
       %{scope: scope} do
    {:ok, _result} = run(scope)

    invoice = invoice(scope, "2020041")
    assert invoice.counter == 41
    assert invoice.date == ~D[2020-09-01]
    assert invoice.due_date == ~D[2020-09-15]
    assert {invoice.service_from, invoice.service_to} == {~D[2020-08-01], ~D[2020-08-31]}
    assert invoice.vat == :rate_16
    assert {invoice.net, invoice.vat_amount, invoice.total} == {95_000, 15_200, 110_200}
    assert invoice.paid_on == ~D[2020-09-10]
    refute invoice.voided

    assert [%{description: "Softwareentwicklung\nAugust 2020", unit: "HUR", unit_price: 9500}] =
             invoice.positions

    assert invoice.recipient.name == "Muster & Söhne GmbH"
    assert invoice.customer_id == Repo.get_by!(Customer, name: "Muster & Söhne GmbH").id

    document = Enum.find(FakePaperless.documents(@url), &(&1.id == invoice.paperless_id))
    assert document.title == "Rechnung 2020041"
    assert document.pdf =~ "Lexoffice Rechnung 2020041"
    assert Invoice.imported?(invoice)
  end

  test "an invoice without a file id has its PDF rendered, and one to a mere address gets a customer of it",
       %{scope: scope} do
    {:ok, _result} = run(scope)

    invoice = invoice(scope, "2026124")
    assert {invoice.service_from, invoice.service_to} == {~D[2026-02-27], ~D[2026-02-27]}
    assert {invoice.net, invoice.vat_amount, invoice.total} == {42_017, 7983, 50_000}
    assert [%{unit: "C62", unit_price: 42_017}] = invoice.positions

    customer = Repo.get!(Customer, invoice.customer_id)

    assert {customer.name, customer.city, customer.lexoffice_id} ==
             {"Jonas Käufer", "Hamburg", nil}

    assert "invoices/bbbbbbbb-0000-4000-8000-000000000003/document" in FakeLexoffice.requests()
  end

  test "a voided invoice stays voided and an open one open, with reverse charge to a customer abroad",
       %{scope: scope} do
    {:ok, _result} = run(scope)

    voided = invoice(scope, "2024102")
    assert voided.voided
    assert voided.paid_on == nil

    open = invoice(scope, "2026125")
    assert open.vat == :reverse_charge
    assert open.paid_on == nil
    assert open.recipient.vat_id == "IT01234567897"
    assert [%{unit: "MON"}, %{unit: "HUR"}] = open.positions
    refute Invoice.settled?(open)
    assert Invoice.settled?(voided)
    refute "payments/bbbbbbbb-0000-4000-8000-000000000004" in FakeLexoffice.requests()
  end

  test "an invoice that cannot come over is skipped before its PDF goes to Paperless", %{
    scope: scope
  } do
    id = "bbbbbbbb-0000-4000-8000-000000000003"
    json = fixture_json("invoices/#{id}")
    stop_supervised!(FakeLexoffice)
    FakeLexoffice.serve(@key, %{"invoices/#{id}" => {:ok, put_in(json["address"]["name"], nil)}})

    assert {:ok, result} = run(scope)
    assert {"2026124", "Die Rechnung hat keinen Empfänger"} in result.skipped
    refute Enum.any?(FakePaperless.documents(@url), &(&1.title == "Rechnung 2026124"))
    refute "invoices/#{id}/document" in FakeLexoffice.requests()
  end

  test "invoices continue the Lexoffice sequence", %{scope: scope} do
    {:ok, _result} = run(scope)
    sender_fixture(scope)
    customer = Repo.get_by!(Customer, name: "Muster & Söhne GmbH")

    assert invoice_fixture(scope, customer, %{"date" => "2027-01-15"}).number == "2027126"
  end

  test "an invoice paid or voided in Lexoffice takes no payment here", %{scope: scope} do
    business = account_fixture(kind: :tracking)
    {:ok, _ids} = Abakus.Bookkeeping.put_business_accounts(scope, [business.id])
    {:ok, _result} = run(scope)

    paid = invoice(scope, "2026124")
    transaction_fixture(%{account_id: business.id, date: ~D[2026-03-05], amount: 50_000})

    assert InvoicePayments.proposals(scope, [paid, invoice(scope, "2024102")]) == %{}
    assert {:error, :paid} = InvoicePayments.confirm(scope, paid, Ecto.UUID.generate())
  end

  test "a customer of the same name made before is linked to the contact and keeps its address",
       %{scope: scope} do
    customer = customer_fixture(scope, %{"name" => "muster & söhne gmbh", "city" => "Augsburg"})
    {:ok, _result} = run(scope)

    assert invoice(scope, "2020041").customer_id == customer.id

    assert Repo.all(
             from c in Customer, where: c.lexoffice_id == "aaaaaaaa-0000-4000-8000-000000000001"
           ) ==
             [Repo.get!(Customer, customer.id)]

    assert Repo.get!(Customer, customer.id).city == "Augsburg"
  end

  test "a key Lexoffice refuses stops the import before anything comes over", %{scope: scope} do
    assert run(scope, "wrong") == {:error, :unauthorized}
    assert Invoices.list_customers(scope) == []
  end

  test "without Paperless the import does not start", %{scope: scope} do
    {:ok, _connection} = Paperless.disconnect(scope)

    assert run(scope) == {:error, :not_connected}
    assert FakeLexoffice.requests() == []
  end

  test "an error of Lexoffice stops the import, and a second run goes on from there", %{
    scope: scope
  } do
    stop_supervised!(FakeLexoffice)

    FakeLexoffice.serve(@key, %{
      "invoices/bbbbbbbb-0000-4000-8000-000000000003" => {:error, :unreachable}
    })

    assert run(scope) == {:error, :unreachable}
    assert Enum.map(Invoices.list_invoices(scope), & &1.number) == ["2024102", "2020041"]

    stop_supervised!(FakeLexoffice)
    FakeLexoffice.serve(@key)

    assert {:ok, %{invoices: 2}} = run(scope)
    assert length(Invoices.list_invoices(scope)) == 4
  end

  test "a voucher Lexoffice or Paperless fails on is skipped and reported, and the rest goes on",
       %{scope: scope} do
    Application.put_env(:abakus, :today, ~D[2026-11-07])
    on_exit(fn -> Application.delete_env(:abakus, :today) end)
    t = business_transactions(scope)
    stop_supervised!(FakeLexoffice)

    FakeLexoffice.serve(@key, %{
      "files/ffffffff-0000-4000-8000-000000000001" => {:error, {:http_status, 415}},
      "vouchers/cccccccc-0000-4000-8000-000000000003" => {:error, :not_found},
      "files/ffffffff-0000-4000-8000-000000000012" => {:error, :too_large}
    })

    assert {:ok, result} = run(scope, @key, year_filed: 2024)
    assert {result.invoices, result.receipts, result.matched} == {3, 4, 2}

    assert result.skipped == [
             {"2020041", "Lexoffice oder Paperless meldet Fehler 415"},
             {"2025110", "Rechnung mit mehreren Steuersätzen"},
             {"NT-88172", "Die Datei ist zu groß"},
             {"SW-2025-1028", "In Lexoffice nicht gefunden"}
           ]

    assert attachments(t.desk) == ["Beleg RE-55120", "Beleg RE-55120 (2)"]
    assert {:euer, 2024} in result.locked
    refute {:euer, 2023} in result.locked

    stop_supervised!(FakeLexoffice)
    FakeLexoffice.serve(@key)

    assert {:ok, %{invoices: 1, receipts: 2, matched: 2}} = run(scope)
    assert attachments(t.internet) == ["Beleg NT-88172"]
  end

  test "a second import of the user is refused while one runs", %{scope: scope} do
    test = self()

    second = fn
      {:customers, _count} -> send(test, {:second, Task.await(Task.async(fn -> run(scope) end))})
      _progress -> :ok
    end

    assert {:ok, %{invoices: 4}} = LexofficeImport.run(scope, fn -> @key end, progress: second)
    assert_received {:second, {:error, :running}}
    assert {:ok, %{invoices: 0}} = run(scope)
  end

  test "another user with the same Lexoffice data imports it all for themselves", %{scope: scope} do
    {:ok, mine} = run(scope)
    other = Scope.for_user(UsersFixtures.user_fixture())
    other_url = "http://paperless-other.test"
    {:ok, _connection} = Paperless.update_connection(other, %{"url" => other_url, "token" => "t"})
    documents = FakePaperless.documents(@url)
    stop_supervised!(FakePaperless)

    FakePaperless.serve(%{
      @url => %{token: "t", documents: documents},
      other_url => %{token: "t", documents: []}
    })

    own = fn s ->
      {Invoices.list_customers(s), Invoices.list_invoices(s),
       Repo.all(from r in owned(LexofficeReceipt, s), order_by: r.id)}
    end

    before = own.(scope)

    assert {:ok, theirs} = run(other)

    assert Map.take(theirs, [:customers, :invoices, :receipts]) ==
             Map.take(mine, [:customers, :invoices, :receipts])

    assert own.(scope) == before
    assert length(elem(own.(other), 2)) == 6

    their_customers = MapSet.new(Invoices.list_customers(other), & &1.id)
    assert MapSet.disjoint?(their_customers, MapSet.new(Invoices.list_customers(scope), & &1.id))
    assert Enum.all?(Invoices.list_invoices(other), &(&1.customer_id in their_customers))
    assert length(FakePaperless.documents(other_url)) == length(FakePaperless.documents(@url))
  end

  test "two waiting receipts with the same payment both go to review", %{scope: scope} do
    t = business_transactions(scope)
    stop_supervised!(FakeLexoffice)

    FakeLexoffice.serve(@key, %{
      "payments/cccccccc-0000-4000-8000-000000000003" =>
        {:ok, fixture_json("payments/cccccccc-0000-4000-8000-000000000002")}
    })

    assert {:ok, %{matched: 2, review: 4}} = run(scope)
    assert attachments(t.internet) == []

    for number <- ["NT-88172", "SW-2025-1028"] do
      assert {_receipt, [proposal]} =
               Enum.find(LexofficeReceipts.review(scope), &(elem(&1, 0).number == number))

      assert proposal.id == t.internet.id
    end
  end

  test "reports each step to the progress callback", %{scope: scope} do
    test = self()

    {:ok, _result} =
      LexofficeImport.run(scope, fn -> @key end, progress: &send(test, {:progress, &1}))

    assert_received {:progress, {:customers, 3}}
    assert_received {:progress, {:invoices, 0, 5}}
    assert_received {:progress, {:invoices, 5, 5}}
    assert_received {:progress, {:receipts, 0, 6}}
    assert_received {:progress, {:receipts, 6, 6}}
  end
end

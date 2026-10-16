defmodule Abakus.Depot.ReceiptsTest do
  use Abakus.DataCase

  # The model's failures are logged.
  @moduletag :capture_log

  import Abakus.Depot.{PortfoliosFixtures, ReceiptsFixtures, SecuritiesFixtures}

  alias Abakus.Depot.{FakeModel, FakeTextExtractor, Portfolios, Receipts}
  alias Abakus.Depot.Portfolios.Receipt
  alias Abakus.Depot.Receipts.{Check, Fields}

  setup do
    scope = Abakus.UsersFixtures.user_scope_fixture()
    Receipts.subscribe(scope)
    account = account_fixture(scope, name: "Verrechnungskonto")
    portfolio = portfolio_fixture(scope, reference_account_id: account.id, depot_number: "4472")
    security = security_fixture(isin: "IE00BK5BQT80")
    %{scope: scope, account: account, portfolio: portfolio, security: security}
  end

  defp upload(scope, path \\ pdf_file()) do
    result = Receipts.upload(scope, path, Path.basename(path))
    await_recognition()
    result
  end

  defp book_params(ctx) do
    %{
      "kind" => "purchase",
      "date" => "2026-10-01",
      "portfolio_id" => ctx.portfolio.id,
      "account_id" => ctx.account.id,
      "security_id" => ctx.security.id,
      "shares" => "93,207",
      "price" => "12,0699",
      "amount" => "1.125,00",
      "amount_set" => "true"
    }
  end

  defp book(ctx, receipt) do
    Receipts.book(ctx.scope, Portfolios.transaction_choices(ctx.scope), book_params(ctx), receipt)
  end

  describe "upload/3" do
    test "checks a purchase whose charge the bank prints with a minus", ctx do
      FakeTextExtractor.stub(receipt_text())
      FakeModel.stub(fn _text -> {:ok, answer(%{"amount" => -1125.0, "fees" => -0.0})} end)

      upload(ctx.scope)

      assert [%Receipt{fields: fields, checks: [%Check{name: :amount, result: :passed} | _]}] =
               Receipts.list_inbox(ctx.scope)

      assert Decimal.equal?(fields.amount, "1125")
    end

    test "reads the PDF's text, has the model recognise it and checks the fields", ctx do
      FakeTextExtractor.stub(receipt_text())
      FakeModel.stub(fn _text -> {:ok, answer()} end)

      assert upload(ctx.scope) == {:ok, :added}
      assert_received {:answer, text}
      assert text =~ "Wertpapierabrechnung Kauf"

      assert [%Receipt{status: :ready} = receipt] = Receipts.list_inbox(ctx.scope)
      assert receipt.text == receipt_text()
      assert receipt.bank_reference == "SP0001"

      assert %Fields{
               kind: :purchase,
               date: ~D[2026-10-01],
               isin: "IE00BK5BQT80",
               depot_number: "4472",
               taxes: nil
             } = receipt.fields

      assert Decimal.equal?(receipt.fields.shares, "93.207")
      assert Decimal.equal?(receipt.fields.price, "12.0699")

      assert [
               %Check{name: :amount, result: :passed} = amount,
               %Check{name: :found, result: :passed},
               %Check{name: :isin, result: :passed},
               %Check{name: :depot, result: :passed} = depot,
               %Check{name: :reference, result: :passed}
             ] = receipt.checks

      assert depot.portfolio_id == ctx.portfolio.id

      assert Decimal.equal?(amount.computed, "1125.00")
      assert Receipts.inbox_count(ctx.scope) == 1
    end

    test "shows „wird erkannt“ until the model is done", ctx do
      FakeTextExtractor.stub(receipt_text())
      test = self()

      FakeModel.stub(fn _text ->
        send(test, {:waiting, self()})
        receive do: (:go -> {:ok, answer()})
      end)

      {:ok, :added} = Receipts.upload(ctx.scope, pdf_file(), "beleg.pdf")
      assert_receive :receipts_updated
      assert_receive {:waiting, task}
      assert [%Receipt{status: :recognising}] = Receipts.list_inbox(ctx.scope)
      assert Receipts.inbox_count(ctx.scope) == 0

      send(task, :go)
      assert_receive :receipts_updated
      assert [%Receipt{status: :ready}] = Receipts.list_inbox(ctx.scope)
      assert Receipts.inbox_count(ctx.scope) == 1
    end

    test "a receipt discarded while the model reads it stays discarded", ctx do
      FakeTextExtractor.stub(receipt_text())
      test = self()

      FakeModel.stub(fn _text ->
        send(test, {:waiting, self()})
        receive do: (:go -> {:ok, answer()})
      end)

      {:ok, :added} = Receipts.upload(ctx.scope, pdf_file(), "beleg.pdf")
      assert_receive {:waiting, task}
      [receipt] = Receipts.list_inbox(ctx.scope)
      :ok = Receipts.discard(ctx.scope, receipt.id)

      send(task, :go)
      await_recognition()

      assert %Receipt{status: :discarded, fields: nil} = Repo.get!(Receipt, receipt.id)
    end

    test "asks the model about one receipt at a time", ctx do
      FakeTextExtractor.stub(receipt_text())
      running = :counters.new(2, [])

      FakeModel.stub(fn _text ->
        :counters.add(running, 1, 1)
        :counters.put(running, 2, max(:counters.get(running, 1), :counters.get(running, 2)))
        Process.sleep(10)
        :counters.sub(running, 1, 1)
        {:ok, answer()}
      end)

      for _n <- 1..5, do: {:ok, :added} = Receipts.upload(ctx.scope, pdf_file(), "beleg.pdf")
      await_recognition()

      assert length(Receipts.list_inbox(ctx.scope)) == 5
      assert :counters.get(running, 2) == 1
    end

    test "Scenario: The same file twice — no second inbox item appears", ctx do
      path = pdf_file()
      {:ok, :added} = upload(ctx.scope, path)

      assert upload(ctx.scope, path) == {:ok, :in_inbox}
      assert [_one] = Receipts.list_inbox(ctx.scope)
    end

    test "brings a discarded receipt back into the inbox", ctx do
      path = pdf_file()
      {:ok, :added} = upload(ctx.scope, path)
      [receipt] = Receipts.list_inbox(ctx.scope)
      assert Receipts.discard(ctx.scope, receipt.id) == :ok
      assert Receipts.list_inbox(ctx.scope) == []

      assert upload(ctx.scope, path) == {:ok, :added}
      assert [%Receipt{id: id, status: :ready}] = Receipts.list_inbox(ctx.scope)
      assert id == receipt.id
    end

    test "tells a file booked already", ctx do
      FakeTextExtractor.stub(receipt_text())
      FakeModel.stub(fn _text -> {:ok, answer()} end)
      path = pdf_file()
      {:ok, :added} = upload(ctx.scope, path)
      receipt = Receipts.get_ready_receipt(ctx.scope, hd(Receipts.list_inbox(ctx.scope)).id)
      {:ok, _transactions} = book(ctx, receipt)

      assert upload(ctx.scope, path) == {:ok, :booked}
      assert Receipts.list_inbox(ctx.scope) == []
    end

    test "refuses a file that is no PDF", ctx do
      path = pdf_file("beleg.pdf", "no pdf")
      assert Receipts.upload(ctx.scope, path, "beleg.pdf") == {:error, :not_pdf}
      assert Receipts.list_inbox(ctx.scope) == []
    end

    test "without a model the receipt waits with its text and no fields", ctx do
      FakeTextExtractor.stub(receipt_text())

      {:ok, :added} = upload(ctx.scope)

      assert [%Receipt{status: :ready, fields: nil, checks: [], text: text}] =
               Receipts.list_inbox(ctx.scope)

      assert text == receipt_text()
    end

    test "a PDF without text waits without fields and without asking the model", ctx do
      FakeModel.stub(fn _text -> {:ok, answer()} end)

      {:ok, :added} = upload(ctx.scope)

      refute_received {:answer, _text}
      assert [%Receipt{status: :ready, fields: nil, text: nil}] = Receipts.list_inbox(ctx.scope)
    end

    test "an answer that misses fields or breaks the schema leaves an empty form", ctx do
      FakeTextExtractor.stub(receipt_text())

      for broken <- [
            ~s({"kind": "purchase", "isin": "IE00BK5BQT80"}),
            answer(%{"shares" => true}),
            answer(%{"kind" => "transfer"}),
            answer(%{"isin" => 42}),
            "Gerne! Hier ist der Beleg: …",
            ~s(["purchase"])
          ] do
        FakeModel.stub(fn _text -> {:ok, broken} end)
        {:ok, :added} = upload(ctx.scope)
      end

      FakeModel.stub(fn _text -> {:error, :unreachable} end)
      {:ok, :added} = upload(ctx.scope)

      inbox = Receipts.list_inbox(ctx.scope)
      assert length(inbox) == 7
      assert Enum.all?(inbox, &match?(%Receipt{status: :ready, fields: nil, checks: []}, &1))
    end

    test "a model that exits leaves an empty form, not a receipt still being recognised", ctx do
      FakeTextExtractor.stub(receipt_text())
      FakeModel.stub(fn _text -> exit(:timeout) end)

      {:ok, :added} = upload(ctx.scope)

      assert [%Receipt{status: :ready, fields: nil}] = Receipts.list_inbox(ctx.scope)
    end

    test "marks any receipt but a purchase, sale or dividend as unsupported", ctx do
      FakeTextExtractor.stub("Depotauszug zum 30.09.2026")
      FakeModel.stub(fn _text -> {:ok, answer(%{"kind" => "other"})} end)

      {:ok, :added} = upload(ctx.scope)

      assert [%Receipt{status: :unsupported, checks: []}] = Receipts.list_inbox(ctx.scope)
    end
  end

  describe "correction round" do
    setup do
      FakeTextExtractor.stub(receipt_text())
      :ok
    end

    test "asks the model once more in the same chat when the amount does not add up", ctx do
      FakeModel.stub(fn
        _text, nil -> {:ok, answer(%{"amount" => 1025.0})}
        _text, _correction -> {:ok, answer()}
      end)

      upload(ctx.scope)

      assert_received {:correction, message}

      assert message ==
               "Stück × Kurs ergibt 1.125,00\u00A0€, du nennst 1.025,00\u00A0€. " <>
                 "Prüfe Betrag, Kurs, Gebühren und Steuern im Beleg. " <>
                 "Betrag 1.025,00\u00A0€ steht nicht im Beleg. " <>
                 "Übernimm nur Werte, die im Beleg stehen. Antworte erneut im selben Schema."

      assert [%Receipt{fields: fields, checks: checks}] = Receipts.list_inbox(ctx.scope)
      assert Decimal.equal?(fields.amount, "1125")
      assert Enum.all?(checks, &(&1.result == :passed))
    end

    test "keeps the first answer unless the second passes more checks" do
      FakeModel.stub(fn
        _text, nil -> {:ok, answer(%{"amount" => 1025.0})}
        _text, _correction -> {:ok, answer(%{"amount" => 1025.0, "price" => 11.0})}
      end)

      assert {:ok, fields, :unfixed} = Receipts.read_fields(receipt_text(), FakeModel)
      assert Decimal.equal?(fields.price, "12.0699")

      FakeModel.stub(fn
        _text, nil -> {:ok, answer(%{"amount" => 1025.0})}
        _text, _correction -> {:error, :timeout}
      end)

      assert {:ok, fields, :unfixed} = Receipts.read_fields(receipt_text(), FakeModel)
      assert Decimal.equal?(fields.amount, "1025")
    end

    test "asks for an invalid ISIN, never more than once, and not when switched off" do
      FakeModel.stub(fn _text -> {:ok, answer(%{"isin" => "IE00BK5BQT81"})} end)

      assert {:ok, _fields, :unfixed} = Receipts.read_fields(receipt_text(), FakeModel)
      assert_received {:correction, "Die ISIN IE00BK5BQT81 hat eine falsche Prüfziffer." <> _}
      refute_received {:correction, _message}

      assert {:ok, _fields, :none} =
               Receipts.read_fields(receipt_text(), FakeModel, correction: false)

      refute_received {:correction, _message}
    end

    test "asks for missing shares, price or amount, naming where shares stand" do
      FakeModel.stub(fn
        _text, nil -> {:ok, answer(%{"shares" => nil, "price" => nil})}
        _text, _correction -> {:ok, answer()}
      end)

      assert {:ok, fields, :fixed} = Receipts.read_fields(receipt_text(), FakeModel)
      assert Decimal.equal?(fields.shares, "93.207")

      assert_received {:correction, message}

      assert message ==
               "Du nennst keine Angabe zu Stück und Kurs. Jeder Kauf hat sie; Stück stehen " <>
                 "etwa bei „Stück“, „St.“, „Stk.“, „STK“, „Anzahl“ oder „Nominale“. " <>
                 "Suche sie im Beleg. Antworte erneut im selben Schema."
    end

    test "keeps a second answer that fills missing values, though its amount does not add up" do
      FakeModel.stub(fn
        _text, nil -> {:ok, answer(%{"shares" => nil})}
        _text, _correction -> {:ok, answer(%{"shares" => "93,207", "taxes" => "12,0699"})}
      end)

      assert {:ok, fields, :unfixed} = Receipts.read_fields(receipt_text(), FakeModel)
      assert Decimal.equal?(fields.shares, "93.207")
    end

    test "does not ask for values not in the text alone, but fails their check", ctx do
      FakeModel.stub(fn _text -> {:ok, answer(%{"date" => "2026-10-02"})} end)

      upload(ctx.scope)

      refute_received {:correction, _message}
      assert [%Receipt{checks: checks}] = Receipts.list_inbox(ctx.scope)

      assert %Check{result: :failed, not_found: [:date]} =
               Enum.find(checks, &(&1.name == :found))
    end
  end

  test "Scenario: A duplicate by bank reference — the inbox marks it as already booked", ctx do
    FakeTextExtractor.stub(receipt_text("SP-0001"))
    FakeModel.stub(fn _text -> {:ok, answer(%{"bank_reference" => "SP-0001"})} end)
    {:ok, :added} = upload(ctx.scope)
    [first] = Receipts.list_inbox(ctx.scope)
    {:ok, _transactions} = book(ctx, Receipts.get_ready_receipt(ctx.scope, first.id))

    {:ok, :added} = upload(ctx.scope)

    assert [%Receipt{status: :ready} = second] = Receipts.list_inbox(ctx.scope)

    assert %Check{result: :failed, booked_on: ~D[2026-10-01]} =
             Enum.find(second.checks, &(&1.name == :reference))

    assert Receipts.discard(ctx.scope, second.id) == :ok
    assert Receipts.list_inbox(ctx.scope) == []
  end

  test "a bank reference is the same however the receipt spaces and cases it" do
    assert Receipt.bank_reference("SP-0001") == Receipt.bank_reference("sp 0001")
    assert Receipt.bank_reference("SP-0001") == "SP0001"
    assert Receipt.bank_reference(" - ") == nil
    assert Receipt.bank_reference(nil) == nil
  end

  test "a duplicate is found though the receipts write the reference differently", ctx do
    FakeTextExtractor.stub(receipt_text("SP-0001"))
    FakeModel.stub(fn _text -> {:ok, answer(%{"bank_reference" => "SP-0001"})} end)
    {:ok, :added} = upload(ctx.scope)
    [first] = Receipts.list_inbox(ctx.scope)
    {:ok, _transactions} = book(ctx, Receipts.get_ready_receipt(ctx.scope, first.id))

    FakeTextExtractor.stub(receipt_text("sp 0001"))
    FakeModel.stub(fn _text -> {:ok, answer(%{"bank_reference" => "sp 0001"})} end)
    {:ok, :added} = upload(ctx.scope)

    assert [second] = Receipts.list_inbox(ctx.scope)
    assert %Check{result: :failed} = Enum.find(second.checks, &(&1.name == :reference))
  end

  test "booking a waiting receipt with the same reference marks it", ctx do
    FakeTextExtractor.stub(receipt_text())
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    {:ok, :added} = upload(ctx.scope)
    {:ok, :added} = upload(ctx.scope)
    [second, first] = Receipts.list_inbox(ctx.scope)

    {:ok, _transactions} = book(ctx, Receipts.get_ready_receipt(ctx.scope, first.id))

    assert [%Receipt{id: id, checks: checks}] = Receipts.list_inbox(ctx.scope)
    assert id == second.id
    assert %Check{result: :failed} = Enum.find(checks, &(&1.name == :reference))
  end

  describe "book/4" do
    setup ctx do
      FakeTextExtractor.stub(receipt_text())
      FakeModel.stub(fn _text -> {:ok, answer()} end)
      {:ok, :added} = upload(ctx.scope)
      [receipt] = Receipts.list_inbox(ctx.scope)
      %{receipt: Receipts.get_ready_receipt(ctx.scope, receipt.id)}
    end

    test "books a transaction from the receipt with its PDF attached", ctx do
      assert {:ok, [transaction]} = book(ctx, ctx.receipt)

      assert %{type: :buy, source: :receipt, amount: 112_500} = transaction
      assert transaction.receipt_id == ctx.receipt.id
      assert Repo.get!(Receipt, ctx.receipt.id).status == :booked
      assert Receipts.list_inbox(ctx.scope) == []
      assert File.exists?(Portfolios.receipt_file(ctx.receipt))
    end

    test "books nothing when the form is invalid", ctx do
      params = Map.put(book_params(ctx), "shares", "")
      choices = Portfolios.transaction_choices(ctx.scope)

      assert {:error, %Ecto.Changeset{}} = Receipts.book(ctx.scope, choices, params, ctx.receipt)
      assert Repo.get!(Receipt, ctx.receipt.id).status == :ready
      assert Portfolios.list_transactions(ctx.scope) == []
    end

    test "books a receipt once only", ctx do
      {:ok, _transactions} = book(ctx, ctx.receipt)

      assert book(ctx, ctx.receipt) == {:error, :gone}
      assert [_one] = Portfolios.list_transactions(ctx.scope)
    end

    test "does not book another user's receipt", ctx do
      other = Abakus.UsersFixtures.user_scope_fixture()
      choices = Portfolios.transaction_choices(ctx.scope)

      assert Receipts.get_ready_receipt(other, ctx.receipt.id) == nil
      assert Receipts.discard(other, ctx.receipt.id) == {:error, :gone}

      assert Portfolios.book_transaction(other, choices, book_params(ctx), ctx.receipt) ==
               {:error, :gone}
    end

    test "attaching the waiting file in the form books it too", ctx do
      path = Portfolios.receipt_file(ctx.receipt)
      choices = Portfolios.transaction_choices(ctx.scope)

      {:ok, [transaction]} =
        Portfolios.book_transaction(ctx.scope, choices, book_params(ctx), {path, "beleg.pdf"})

      assert transaction.receipt_id == ctx.receipt.id
      assert Receipts.list_inbox(ctx.scope) == []
    end
  end

  test "recognises again the receipts still being recognised at the stop", ctx do
    FakeTextExtractor.stub(receipt_text())
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    path = pdf_file()
    {:ok, sha256} = Portfolios.store_receipt_file(File.read!(path))

    Repo.insert!(%Receipt{
      user_id: ctx.scope.user.id,
      sha256: sha256,
      filename: "beleg.pdf",
      byte_size: 10,
      status: :recognising
    })

    Receipts.resume_recognition()

    await_recognition()
    assert [%Receipt{status: :ready, fields: %Fields{}}] = Receipts.list_inbox(ctx.scope)
  end
end

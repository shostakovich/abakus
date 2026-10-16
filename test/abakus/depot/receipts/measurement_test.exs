defmodule Abakus.Depot.Receipts.MeasurementTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.ReceiptsFixtures

  alias Abakus.Depot.Receipts.{Fields, Measurement}

  defmodule Extractor do
    @behaviour Abakus.Depot.Receipts.TextExtractor

    @impl true
    def text(path), do: if(String.contains?(path, "scan"), do: :error, else: {:ok, "PDF text"})
  end

  defp fields(changes \\ %{}) do
    {:ok, fields} = Fields.from_answer(answer(changes))
    fields
  end

  defp result(label, receipt, seconds, wrong \\ [], error \\ nil, correction \\ :none) do
    right = Map.new(Measurement.fields(), &{&1, &1 not in wrong})

    %{
      label: label,
      receipt: receipt,
      seconds: seconds,
      error: error,
      right: right,
      correction: if(error, do: nil, else: correction),
      not_found: false
    }
  end

  describe "receipts/2" do
    test "reads the synthetic receipts with their expected fields" do
      receipts = Measurement.receipts("test/fixtures/depot/receipts/synthetic", Extractor)

      assert [before_taxes, dividend, _fractional, _other_purchase, purchase, _plan, _sale] =
               receipts

      assert Enum.map(receipts, & &1.name) == Enum.sort(Enum.map(receipts, & &1.name))
      assert Enum.all?(receipts, & &1.expected)

      assert dividend.name == "dividende.txt"
      assert dividend.text =~ "Dividendengutschrift"
      assert %Fields{kind: :dividend, isin: "DE0007164600"} = dividend.expected

      assert before_taxes.name == "dividende-vor-steuern.txt"
      assert before_taxes.text =~ "separaten Steuermitteilung"
      assert %Fields{kind: :dividend, amount: amount, taxes: taxes} = before_taxes.expected
      assert Decimal.equal?(amount, "184.80") and Decimal.equal?(taxes, 0)

      assert purchase.name == "kauf.pdf"
      assert purchase.text == "PDF text"
      assert purchase.expected_path == "test/fixtures/depot/receipts/synthetic/kauf.expected.json"
      assert %Fields{kind: :purchase, fees: fees, taxes: nil} = purchase.expected
      assert Decimal.equal?(fees, "6.45")
    end

    test "leaves out a PDF without text and anything else, keeps one without expected fields" do
      folder = Path.dirname(pdf_file("neu.pdf"))
      File.write!(Path.join(folder, "scan.pdf"), "%PDF")
      File.write!(Path.join(folder, "notiz.md"), "")

      assert [%{name: "neu.pdf", expected: nil}] = Measurement.receipts(folder, Extractor)
    end

    test "scores only the fields an expected file knows" do
      folder = Path.dirname(pdf_file("neu.pdf"))
      expected = answer() |> JSON.decode!() |> Map.put("unscored", ["price", "depot_number"])
      File.write!(Path.join(folder, "neu.expected.json"), JSON.encode!(expected))

      assert [%{scored: scored}] = Measurement.receipts(folder, Extractor)
      assert scored == Measurement.fields() -- [:price, :depot_number]
    end

    test "refuses an expected file off the schema" do
      folder = Path.dirname(pdf_file("neu.pdf"))
      File.write!(Path.join(folder, "neu.expected.json"), ~s({"kind": "purchase"}))

      assert_raise ArgumentError, ~r/neu.expected.json/, fn ->
        Measurement.receipts(folder, Extractor)
      end
    end
  end

  describe "right/2" do
    test "takes numbers by value, no fees or taxes as zero, depot digits, references without blanks" do
      answer =
        fields(%{
          "shares" => "93.2070",
          "fees" => nil,
          "taxes" => 0,
          "depot_number" => "44-72",
          "bank_reference" => "SP - 0001"
        })

      assert Measurement.right(fields(), {:ok, answer}) |> Map.values() |> Enum.all?()
    end

    test "counts a different value wrong" do
      answer = fields(%{"date" => "2026-10-02", "amount" => 1125.01, "kind" => "sale"})

      assert %{date: false, amount: false, kind: false, isin: true} =
               Measurement.right(fields(), {:ok, answer})
    end

    test "counts every field of a failed answer wrong" do
      refute Measurement.right(fields(), {:error, :off_schema}) |> Map.values() |> Enum.any?()
    end
  end

  test "run/3 times each receipt with expected fields and records its errors" do
    receipts = [
      %{name: "a.pdf", text: receipt_text(), expected: fields()},
      %{name: "b.pdf", text: "b", expected: nil},
      %{name: "c.txt", text: "c", expected: fields()}
    ]

    recognise = fn
      "c" -> {:error, :off_schema}
      _text -> {:ok, fields(%{"shares" => 1}), :fixed}
    end

    receipts = Enum.map(receipts, &Map.put(&1, :scored, Measurement.fields() -- [:price]))
    assert [a, c] = Measurement.run(receipts, "gemma", recognise)
    refute Map.has_key?(a.right, :price)

    assert %{label: "gemma", receipt: "a.pdf", error: nil, right: %{shares: false, fees: true}} =
             a

    assert %{correction: :fixed, not_found: true} = a
    assert a.seconds >= 0

    assert %{receipt: "c.txt", error: :off_schema, right: %{kind: false}, correction: nil} = c
    refute c.not_found
  end

  test "summarise/1 gives the share right per field and overall, failures and times per label" do
    results = [
      result("qwen", "a.pdf", 10.0),
      result("qwen", "b.pdf", 30.0, [:fees, :taxes]),
      result("gemma", "a.pdf", 2.0, Measurement.fields(), :off_schema),
      result("gemma", "b.pdf", 4.0, [], nil, :fixed),
      result("gemma", "c.pdf", 3.0, [], nil, :unfixed) |> Map.put(:not_found, true)
    ]

    assert [qwen, gemma] = Measurement.summarise(results)

    assert %{label: "qwen", receipts: 2, failed: 0, mean: 20.0, median: 20.0, max: 30.0} = qwen
    assert qwen.fields.fees == 0.5
    assert qwen.fields.kind == 1.0
    assert qwen.overall == 0.9
    assert qwen.wrong == [{"b.pdf", nil, [:fees, :taxes]}]

    assert %{receipts: 3, failed: 1, median: 3.0, max: 4.0} = gemma
    assert %{corrections: 0, fixed: 0, not_found: 0} = qwen
    assert %{corrections: 2, fixed: 1, not_found: 1} = gemma
    assert gemma.mean == 3.0
    assert_in_delta gemma.overall, 2 / 3, 0.0001
  end

  test "summarise/1 shares only scored fields and none for a field never scored" do
    unscored = fn result -> Map.update!(result, :right, &Map.drop(&1, [:price, :fees])) end

    [summary] =
      Measurement.summarise([
        unscored.(result("qwen", "a.txt", 1.0, [:fees, :taxes])),
        result("qwen", "b.pdf", 1.0, [:fees])
      ])

    assert summary.fields.price == 1.0
    assert summary.fields.fees == 0.0
    assert summary.fields.taxes == 0.5
    assert summary.overall == 16 / 18
    assert summary.wrong == [{"a.txt", nil, [:taxes]}, {"b.pdf", nil, [:fees]}]

    [summary] = Measurement.summarise([unscored.(result("qwen", "a.txt", 1.0))])
    assert summary.fields.price == nil
    assert Measurement.table([summary]) =~ ~r/\nprice\s+-\n/
  end

  test "sample/2 spreads the receipts taken over all of them" do
    assert Measurement.sample(Enum.to_list(1..10), 3) == [1, 4, 7]
    assert Measurement.sample([1, 2], 5) == [1, 2]
  end

  test "table/1 puts a column per label and the wrong fields below" do
    table =
      Measurement.table(
        Measurement.summarise([
          result("qwen", "a.pdf", 12.34, [:fees]),
          result("gemma", "a.pdf", 2.0, Measurement.fields(), :off_schema)
        ])
      )

    lines = String.split(table, "\n")
    assert Enum.at(lines, 0) =~ ~r/^\s+qwen\s+gemma$/
    assert "fees" <> _ = fees = Enum.find(lines, &String.starts_with?(&1, "fees"))
    assert fees =~ ~r/0 %\s+0 %$/
    assert Enum.find(lines, &String.starts_with?(&1, "all fields")) =~ ~r/90 %\s+0 %$/
    assert Enum.find(lines, &String.starts_with?(&1, "failed answers")) =~ ~r/0\s+1$/
    assert Enum.find(lines, &String.starts_with?(&1, "corrections")) =~ ~r/0\s+0$/
    assert Enum.find(lines, &String.starts_with?(&1, "fixed by them")) =~ ~r/0\s+0$/
    assert Enum.find(lines, &String.starts_with?(&1, "values not in text")) =~ ~r/0\s+0$/
    assert Enum.find(lines, &String.starts_with?(&1, "mean s")) =~ ~r/12\.3\s+2\.0$/
    assert table =~ "Wrong with qwen:\n  a.pdf: fees\n"
    assert table =~ "Wrong with gemma:\n  a.pdf: failed (:off_schema)\n"

    all_right = Measurement.table(Measurement.summarise([result("qwen", "a.pdf", 1.0)]))
    refute all_right =~ "Wrong"
    refute all_right =~ "\n\n"
  end

  test "json/1 encodes results and summaries" do
    json = Measurement.json([result("qwen", "a.pdf", 1.0, [:fees], {:http_status, 500})])

    assert %{"summaries" => [%{"label" => "qwen", "wrong" => [wrong]}], "results" => [result]} =
             JSON.decode!(json)

    assert wrong == %{
             "receipt" => "a.pdf",
             "error" => "{:http_status, 500}",
             "fields" => ["fees"]
           }

    assert result["right"]["fees"] == false
  end

  test "expected_json/1 writes the fields back in the answer format" do
    fields = fields(%{"taxes" => nil, "shares" => 93.207})

    assert {:ok, %Fields{security_name: "Vanguard FTSE All-World U.ETF"}} =
             written = Fields.from_answer(Measurement.expected_json(fields))

    assert Measurement.right(fields, written) |> Map.values() |> Enum.all?()
    assert Measurement.expected_json(fields) =~ ~s("shares": 93.207)
  end
end

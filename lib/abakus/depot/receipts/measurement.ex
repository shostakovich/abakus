defmodule Abakus.Depot.Receipts.Measurement do
  @moduledoc """
  Measures receipt models (#39): how many fields a model recognises right on receipts whose right
  fields are known, and how long it takes per receipt. A receipt is a PDF or a `.txt` text in a
  folder, with its fields in `<name>.expected.json` next to it, in the model's answer format. An
  expected file may list fields it does not know under `"unscored"`; they are not measured.

  Fields count as right as the app uses them: numbers by value, missing fees or taxes as zero,
  the depot number by its digits, the bank's reference without blanks.
  """

  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.Depot.Receipts.{Fields, Matching}

  @fields [
    :kind,
    :date,
    :isin,
    :shares,
    :price,
    :fees,
    :taxes,
    :amount,
    :depot_number,
    :bank_reference
  ]

  @doc "The fields measured, in the order of the table."
  def fields, do: @fields

  @doc """
  The receipts in `folder` with their text, read by `extractor` for a PDF, sorted by name, as
  `%{name, path, expected_path, text, expected, scored}`; `expected` is nil without an expected
  file, `scored` the fields it knows. Receipts without a text are left out.
  """
  def receipts(folder, extractor) do
    folder
    |> File.ls!()
    |> Enum.filter(&(Path.extname(&1) in [".pdf", ".txt"]))
    |> Enum.sort()
    |> Enum.map(&Path.join(folder, &1))
    |> Enum.flat_map(fn path ->
      case text(path, extractor) do
        {:ok, text} -> [receipt(path, text)]
        :error -> []
      end
    end)
  end

  defp text(path, extractor) do
    if Path.extname(path) == ".txt", do: File.read(path), else: extractor.text(path)
  end

  defp receipt(path, text) do
    expected_path = Path.rootname(path) <> ".expected.json"

    {expected, scored} =
      if File.exists?(expected_path), do: expected!(expected_path), else: {nil, @fields}

    %{
      name: Path.basename(path),
      path: path,
      expected_path: expected_path,
      text: text,
      expected: expected,
      scored: scored
    }
  end

  defp expected!(path) do
    json = File.read!(path)

    with {:ok, fields} <- Fields.from_answer(json),
         {:ok, unscored} <- unscored(JSON.decode!(json)) do
      {fields, Enum.reject(@fields, &(Atom.to_string(&1) in unscored))}
    else
      :error -> raise ArgumentError, "#{path} is no answer by the schema"
    end
  end

  defp unscored(%{"unscored" => unscored}) when is_list(unscored), do: {:ok, unscored}
  defp unscored(%{"unscored" => _unscored}), do: :error
  defp unscored(_json), do: {:ok, []}

  @doc "`count` of the receipts, spread evenly over them."
  def sample(receipts, count) when count >= length(receipts), do: receipts

  def sample(receipts, count) do
    step = length(receipts) / count
    for i <- 0..(count - 1), do: Enum.at(receipts, floor(i * step))
  end

  @doc """
  Has `recognise`, a function of a receipt's text returning `{:ok, %Fields{}, correction}` as
  `Abakus.Depot.Receipts.read_fields/3` does or `{:error, reason}`, read each receipt with
  expected fields, as `label`; returns a result per receipt with which fields it got right, the
  seconds it took, how its correction round went, nil for a failed answer, and whether the
  fields kept have values not in the text.
  """
  def run(receipts, label, recognise) do
    for %{expected: %Fields{} = expected} = receipt <- receipts do
      {microseconds, answer} = :timer.tc(fn -> recognise.(receipt.text) end)
      fields = fields(answer)

      %{
        label: label,
        receipt: receipt.name,
        seconds: microseconds / 1_000_000,
        error: error(answer),
        right: right(expected, fields, receipt.scored),
        correction: correction(answer),
        not_found:
          match?({:ok, _fields}, fields) and Matching.missing(receipt.text, elem(fields, 1)) != []
      }
    end
  end

  defp fields({:ok, fields, _correction}), do: {:ok, fields}
  defp fields(error), do: error

  defp error({:ok, _fields, _correction}), do: nil
  defp error({:error, reason}), do: reason

  defp correction({:ok, _fields, correction}), do: correction
  defp correction({:error, _reason}), do: nil

  @doc """
  Whether each of the `scored` fields of `answer` is the expected one; all wrong for a failed
  answer.
  """
  def right(expected, answer, scored \\ @fields)

  def right(%Fields{} = expected, {:ok, %Fields{} = fields}, scored),
    do: Map.new(scored, &{&1, same?(&1, Map.get(expected, &1), Map.get(fields, &1))})

  def right(%Fields{}, {:error, _reason}, scored), do: Map.new(scored, &{&1, false})

  defp same?(field, expected, actual) when field in [:fees, :taxes],
    do: same?(:amount, expected || Decimal.new(0), actual || Decimal.new(0))

  defp same?(_field, %Decimal{} = expected, %Decimal{} = actual),
    do: Decimal.equal?(expected, actual)

  defp same?(:depot_number, expected, actual),
    do: Portfolio.digits(expected) == Portfolio.digits(actual)

  defp same?(:bank_reference, expected, actual), do: blankless(expected) == blankless(actual)
  defp same?(_field, expected, actual), do: expected == actual

  defp blankless(nil), do: nil
  defp blankless(text), do: String.replace(text, ~r/\s/u, "")

  @doc """
  Per label, in the order of `results`: the share of each field right, nil where none was
  scored, of all fields, the answers off the schema or failed, the correction rounds run and
  those that fixed the checks, the answers with values not in the text, and the mean, median and
  longest seconds per receipt.
  """
  def summarise(results) do
    results
    |> Enum.chunk_by(& &1.label)
    |> Enum.map(&summary/1)
  end

  defp summary([%{label: label} | _rest] = results) do
    seconds = results |> Enum.map(& &1.seconds) |> Enum.sort()
    count = length(results)

    %{
      label: label,
      receipts: count,
      failed: Enum.count(results, & &1.error),
      corrections: Enum.count(results, &(&1.correction in [:fixed, :unfixed])),
      fixed: Enum.count(results, &(&1.correction == :fixed)),
      not_found: Enum.count(results, & &1.not_found),
      fields: Map.new(@fields, &{&1, share(results, [&1])}),
      overall: share(results, @fields),
      mean: Enum.sum(seconds) / count,
      median: median(seconds),
      max: List.last(seconds),
      wrong: wrong(results)
    }
  end

  defp share(results, fields) do
    scored =
      for result <- results,
          field <- fields,
          Map.has_key?(result.right, field),
          do: result.right[field]

    if scored != [],
      do: Enum.count(scored, & &1) / length(scored),
      else: nil
  end

  defp median(sorted) do
    middle = div(length(sorted), 2)

    if rem(length(sorted), 2) == 1,
      do: Enum.at(sorted, middle),
      else: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
  end

  defp wrong(results) do
    for result <- results,
        fields = Enum.filter(@fields, &(result.right[&1] == false)),
        fields != [],
        do: {result.receipt, result.error, fields}
  end

  @doc "The summaries as a table, a column per label, then the wrong fields per receipt."
  def table(summaries) do
    rows =
      [["", Enum.map(summaries, & &1.label)], ["receipts", Enum.map(summaries, & &1.receipts)]] ++
        Enum.map(@fields, fn field ->
          [Atom.to_string(field), Enum.map(summaries, &percent(&1.fields[field]))]
        end) ++
        [
          ["all fields", Enum.map(summaries, &percent(&1.overall))],
          ["failed answers", Enum.map(summaries, & &1.failed)],
          ["corrections", Enum.map(summaries, & &1.corrections)],
          ["fixed by them", Enum.map(summaries, & &1.fixed)],
          ["values not in text", Enum.map(summaries, & &1.not_found)],
          ["mean s", Enum.map(summaries, &seconds(&1.mean))],
          ["median s", Enum.map(summaries, &seconds(&1.median))],
          ["max s", Enum.map(summaries, &seconds(&1.max))]
        ]

    [columns(rows) | Enum.map(summaries, &wrong_lines/1)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp columns(rows) do
    rows = Enum.map(rows, fn [name, cells] -> [name | Enum.map(cells, &to_string/1)] end)

    widths =
      rows
      |> Enum.zip_with(& &1)
      |> Enum.map(fn column -> column |> Enum.map(&String.length/1) |> Enum.max() end)

    Enum.map_join(rows, "\n", fn [name | cells] ->
      [String.pad_trailing(name, hd(widths)) | pad_leading(cells, tl(widths))]
      |> Enum.join("  ")
      |> String.trim_trailing()
    end) <> "\n"
  end

  defp pad_leading(cells, widths), do: Enum.zip_with(cells, widths, &String.pad_leading/2)

  defp wrong_lines(%{wrong: []}), do: ""

  defp wrong_lines(%{label: label, wrong: wrong}) do
    lines =
      Enum.map(wrong, fn {receipt, error, fields} ->
        "  #{receipt}: " <>
          if(error, do: "failed (#{inspect(error)})", else: Enum.join(fields, ", "))
      end)

    Enum.join(["Wrong with #{label}:" | lines], "\n") <> "\n"
  end

  defp percent(nil), do: "-"
  defp percent(share), do: "#{round(share * 100)} %"
  defp seconds(seconds), do: :erlang.float_to_binary(seconds / 1, decimals: 1)

  @doc "The results and their summaries as JSON."
  def json(results) do
    summaries = for summary <- summarise(results), do: Map.update!(summary, :wrong, &wrong_json/1)
    results = Enum.map(results, &Map.update!(&1, :error, fn error -> error_json(error) end))
    JSON.encode!(%{summaries: summaries, results: results})
  end

  defp wrong_json(wrong) do
    for {receipt, error, fields} <- wrong,
        do: %{receipt: receipt, error: error_json(error), fields: fields}
  end

  defp error_json(nil), do: nil
  defp error_json(error), do: inspect(error)

  @doc "The fields as an expected file, in the model's answer format, to correct by hand."
  def expected_json(%Fields{} = fields) do
    [:security_name | @fields]
    |> Map.new(&{Atom.to_string(&1), json_value(Map.get(fields, &1))})
    |> :json.format()
    |> IO.iodata_to_binary()
  end

  defp json_value(nil), do: :null
  defp json_value(%Decimal{} = number), do: Decimal.to_float(number)
  defp json_value(%Date{} = date), do: Date.to_iso8601(date)
  defp json_value(value), do: value
end

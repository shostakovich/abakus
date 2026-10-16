defmodule Mix.Tasks.Abakus.MeasureReceipts do
  @shortdoc "Measures receipt models on receipts with known fields"
  @moduledoc """
  Measures how well and how fast models read receipts, the way the inbox does: the text from
  `pdftotext` (or a `.txt` file), the model's answer by the schema, its fields as the app reads
  them. Each receipt in FOLDER needs its right fields in `<name>.expected.json` next to it. Each
  model first reads one receipt untimed, so that loading it does not count.

      mix abakus.measure_receipts [FOLDER] --model gemma4:e4b --model gemma4:26b \\
        --url http://localhost:11434/v1 --thinking both --json results.json

  FOLDER is `test/fixtures/depot/receipts/private` by default. `--url` and `--model` default to
  `RECEIPT_MODEL_URL` and `RECEIPT_MODEL`, the key comes from `RECEIPT_MODEL_KEY`. `--thinking`
  is `off` (default), `on` or `both`. `--correction` is `on` (default, as in the app), `off` or
  `both`: whether the model may correct an answer whose amount or ISIN fails the checks or which
  misses shares, price or amount, see `Abakus.Depot.Receipts.read_fields/3`; the table counts the
  rounds and those that fixed the checks.

  `--sample N` measures only N receipts, spread over the folder's.

  `--style nuextract` asks an extraction model such as NuExtract in its own input format, see
  `Abakus.Depot.Receipts.NuExtract`, with `--prelude TEXT` before its template; it cannot
  correct itself.

  `--write-expected` writes the first model's answer as the expected file of each receipt without
  one, to correct by hand; it overwrites none.

  `--fetch-pp comdirect,scalablecapital` fetches Portfolio Performance's anonymised test texts of
  these banks with expected files into FOLDER, `test/fixtures/depot/receipts/pp` by default, which git
  ignores; see `Abakus.Depot.Receipts.PPCorpus`.
  """
  use Mix.Task

  alias Abakus.Depot.Receipts
  alias Abakus.Depot.Receipts.{ChatAPI, Measurement, NuExtract, Pdftotext, PPCorpus}

  @switches [
    model: :keep,
    url: :string,
    thinking: :string,
    correction: :string,
    json: :string,
    write_expected: :boolean,
    sample: :integer,
    fetch_pp: :string,
    style: :string,
    prelude: :string
  ]
  @switch %{"off" => [false], "on" => [true], "both" => [false, true]}

  @impl true
  def run(args) do
    {options, rest} = OptionParser.parse!(args, strict: @switches)
    if length(rest) > 1, do: Mix.raise("Name one folder")
    if options[:sample] && options[:sample] < 1, do: Mix.raise("--sample needs at least 1")
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started([:inets, :ssl])

    if options[:fetch_pp],
      do: fetch_pp(options[:fetch_pp], List.first(rest, "test/fixtures/depot/receipts/pp")),
      else: measure_or_write(options, List.first(rest, "test/fixtures/depot/receipts/private"))
  end

  defp fetch_pp(banks, folder) do
    for {bank, result} <- PPCorpus.fetch(String.split(banks, ",", trim: true), folder) do
      case result do
        {:ok, written, skipped} ->
          Mix.shell().info("#{bank}: #{written} receipts, #{skipped} texts skipped")

        {:error, reason} ->
          Mix.shell().error("#{bank}: #{inspect(reason)}")
      end
    end
  end

  defp measure_or_write(options, folder) do
    receipts = Measurement.receipts(folder, Pdftotext)
    if receipts == [], do: Mix.raise("No receipts with a text in #{folder}")

    model_options = %{
      models: models(options),
      url: url(options),
      thinking: switch(options, :thinking, "off"),
      correction: switch(options, :correction, "on"),
      json: options[:json],
      sample: options[:sample],
      model: if(options[:style] == "nuextract", do: NuExtract, else: ChatAPI),
      prelude: options[:prelude]
    }

    if options[:write_expected],
      do: write_expected(receipts, model_options),
      else: measure(receipts, model_options)
  end

  defp models(options) do
    case Keyword.get_values(options, :model) do
      [] ->
        [present(System.get_env("RECEIPT_MODEL"), "Name a model with --model or RECEIPT_MODEL")]

      models ->
        models
    end
  end

  defp url(options) do
    present(
      options[:url] || System.get_env("RECEIPT_MODEL_URL"),
      "Name the chat API with --url or RECEIPT_MODEL_URL"
    )
  end

  defp switch(options, name, default) do
    Map.get(@switch, options[name] || default) || Mix.raise("--#{name} is on, off or both")
  end

  defp present(value, message), do: if(value in [nil, ""], do: Mix.raise(message), else: value)

  defp measure(receipts, options) do
    measured = Enum.filter(receipts, & &1.expected)

    for receipt <- receipts -- measured,
        do: Mix.shell().info("#{receipt.name} has no expected file, skipped")

    if measured == [], do: Mix.raise("No receipt has an expected file; try --write-expected")
    measured = if options.sample, do: Measurement.sample(measured, options.sample), else: measured

    results =
      for model <- options.models,
          thinking <- options.thinking,
          correction <- options.correction do
        label = label(model, thinking, correction)
        Mix.shell().info("Measuring #{label} on #{length(measured)} receipts...")
        configure(options, model, thinking)
        Receipts.read_fields(hd(measured).text, options.model, correction: false)

        Measurement.run(
          measured,
          label,
          &Receipts.read_fields(&1, options.model, correction: correction)
        )
      end
      |> List.flatten()

    Mix.shell().info("\n" <> Measurement.table(Measurement.summarise(results)))
    if options.json, do: File.write!(options.json, Measurement.json(results))
  end

  defp label(model, thinking, correction) do
    case Enum.reject([thinking && "thinking", correction && "correction"], &(!&1)) do
      [] -> model
      notes -> "#{model} (#{Enum.join(notes, ", ")})"
    end
  end

  defp write_expected(receipts, options) do
    configure(options, hd(options.models), hd(options.thinking))

    for receipt <- receipts, !receipt.expected do
      case Receipts.read_fields(receipt.text, options.model, correction: hd(options.correction)) do
        {:ok, fields, _correction} ->
          File.write!(receipt.expected_path, Measurement.expected_json(fields) <> "\n")
          Mix.shell().info("Wrote #{receipt.expected_path}, check it by hand")

        {:error, reason} ->
          Mix.shell().error("#{receipt.name}: #{inspect(reason)}")
      end
    end
  end

  defp configure(options, model, thinking) do
    Application.put_env(:abakus, ChatAPI,
      url: options.url,
      model: model,
      api_key: System.get_env("RECEIPT_MODEL_KEY"),
      thinking: thinking,
      prelude: options.prelude
    )
  end
end

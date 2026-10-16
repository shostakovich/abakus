defmodule Abakus.Depot.Receipts.PPCorpus do
  @moduledoc """
  Portfolio Performance's anonymised receipt texts as a local corpus for the measurement: the
  texts of its PDF importer tests per bank, with expected files derived from the tests' asserts.
  Portfolio Performance is EPL-licensed, so the corpus is fetched into an ignored folder and never
  committed.

  Only tests of a single purchase, sale or dividend with ISIN, date, shares, amount, fees and
  taxes become cases, none in a foreign currency, as Portfolio Performance converts its amounts.
  A dividend that leaves the taxes to a separate notice is booked before them, as the app does.
  The texts are PDFBox's, not `pdftotext`'s layout, and their depot numbers and references are
  placeholders, so price, depot number and reference are not scored.
  """

  alias Abakus.Depot.MarketData.HTTP

  @repo "https://api.github.com/repos/portfolio-performance/portfolio/contents/"
  @dir "name.abuchen.portfolio.tests/src/name/abuchen/portfolio/datatransfer/pdf/"
  @kinds ~w(purchase sale dividend)
  @unscored ~w(price depot_number bank_reference)

  @doc """
  Fetches the texts of each of `banks`, Portfolio Performance's folder names such as
  `scalablecapital`, with their expected files into `folder`, replacing those fetched before;
  returns per bank the number of cases written and of texts skipped, or the error.
  """
  def fetch(banks, folder) do
    File.mkdir_p!(folder)
    Map.new(banks, &{&1, fetch_bank(&1, folder)})
  end

  defp fetch_bank(bank, folder) do
    with {:ok, files} <- get_json(@repo <> @dir <> bank, ref: "master"),
         {:ok, tests} <- download_all(test_classes(files)) do
      urls = Map.new(files, &{&1["name"], &1["download_url"]})
      {cases, skipped} = cases(Enum.join(tests, "\n"))
      Enum.each(Path.wildcard(Path.join(folder, "#{bank}-*")), &File.rm!/1)
      written = Enum.count(cases, &write_case(&1, bank, urls[elem(&1, 0)], folder))
      {:ok, written, skipped + length(cases) - written}
    end
  end

  defp test_classes(files) do
    for %{"name" => name, "download_url" => url} <- files,
        String.ends_with?(name, "PDFExtractorTest.java"),
        do: url
  end

  defp download_all(urls) do
    Enum.reduce_while(urls, {:ok, []}, fn url, {:ok, bodies} ->
      case download(url) do
        {:ok, body} -> {:cont, {:ok, [body | bodies]}}
        error -> {:halt, error}
      end
    end)
  end

  defp write_case({_name, _expected}, _bank, nil, _folder), do: false

  defp write_case({name, expected}, bank, url, folder) do
    case download(url) do
      {:ok, text} ->
        path = Path.join(folder, "#{bank}-#{name}")
        File.write!(path, text(text))
        File.write!(Path.rootname(path) <> ".expected.json", JSON.encode!(expected))
        true

      {:error, _reason} ->
        false
    end
  end

  defp get_json(url, params) do
    case HTTP.get(url, params) do
      {:ok, 200, body} -> JSON.decode(body)
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp download(url) do
    case HTTP.get(url, []) do
      {:ok, 200, body} -> {:ok, body}
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "A test text without the PDFBox and version lines Portfolio Performance puts on top."
  def text(text) do
    case String.split(text, ~r/^-{5,}\s*$/m, parts: 2) do
      [head, body] -> if head =~ "PDFBox", do: String.trim_leading(body, "\n"), else: text
      [_text] -> text
    end
  end

  @doc """
  The cases of a Java test class: `{text file, expected answer}` per text with a test of a
  single purchase, sale or dividend, and the number of texts without one.
  """
  def cases(java) do
    tests =
      java
      |> String.split("@Test")
      |> Enum.flat_map(&test_case/1)

    by_file = Enum.group_by(tests, &elem(&1, 0), &elem(&1, 1))

    cases =
      for {file, expectations} <- by_file,
          expected = Enum.find(expectations, & &1),
          do: {file, expected}

    {Enum.sort(cases), map_size(by_file) - length(cases)}
  end

  defp test_case(test) do
    case Regex.scan(~r/loadTestCase\(getClass\(\), "([^"]+\.txt)"\)/, test) do
      [[_call, file]] -> [{file, expected(test)}]
      _none_or_several -> []
    end
  end

  defp expected(test) do
    with [kind] <- transaction_kinds(test),
         true <- kind in @kinds,
         false <- test =~ "hasForexGrossValue(",
         [isin] <- scan(test, ~r/hasIsin\("([A-Z]{2}[A-Z0-9]{9}[0-9])"\)/),
         [date] <- scan(test, ~r/hasDate\("(\d{4}-\d{2}-\d{2})/),
         [shares] <- scan(test, ~r/hasShares\(([\d.]+)\)/),
         [amount] <- scan(test, ~r/hasAmount\("[A-Z]{3}", ([\d.]+)\)/),
         [fees] <- scan(test, ~r/hasFees\("[A-Z]{3}", ([\d.]+)\)/),
         [taxes] <- scan(test, ~r/hasTaxes\("[A-Z]{3}", ([\d.]+)\)/) do
      %{
        kind: kind,
        date: date,
        isin: isin,
        security_name: nil,
        shares: shares,
        price: nil,
        fees: fees,
        taxes: taxes,
        amount: amount,
        depot_number: nil,
        bank_reference: nil,
        unscored: @unscored
      }
    else
      _other -> nil
    end
  end

  defp transaction_kinds(test) do
    for [_item, kind] <- Regex.scan(~r/hasItem\((\w+)\(/, test), kind != "security", do: kind
  end

  defp scan(test, regex), do: for([_match, value] <- Regex.scan(regex, test), do: value)
end

defmodule Abakus.ExchangeRates.ECB do
  @moduledoc "Daily reference rates of all currencies from the ECB Data Portal, in one request."
  @behaviour Abakus.ExchangeRates.Source

  alias Abakus.HTTP

  @url "https://data-api.ecb.europa.eu/service/data/EXR/D..EUR.SP00.A"
  @max_rate Decimal.new("1e9")

  # The ECB blocks requests that start after today, so `from` must not be in the future.
  @impl true
  def rates(from) do
    params = [format: "csvdata", detail: "dataonly", startPeriod: Date.to_iso8601(from)]

    case HTTP.get(@url, params: params, follow_redirects: true) do
      {:ok, 200, body} -> parse(body)
      {:ok, 404, _body} -> {:ok, []}
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Reads the CSV; rows without a value above 0 and up to 10⁹ are skipped."
  def parse(csv) do
    case String.split(csv, ["\r\n", "\n"], trim: true) do
      [] -> {:ok, []}
      [header | rows] -> read(String.split(header, ","), rows)
    end
  end

  defp read(header, rows) do
    columns =
      Enum.map(
        ~w(CURRENCY TIME_PERIOD OBS_VALUE),
        &Enum.find_index(header, fn name -> name == &1 end)
      )

    if Enum.any?(columns, &is_nil/1) do
      {:error, :invalid_response}
    else
      {:ok, Enum.flat_map(rows, &row(String.split(&1, ","), columns))}
    end
  end

  defp row(fields, columns) do
    [currency, date, value] = Enum.map(columns, &Enum.at(fields, &1))

    with {:ok, date} <- Date.from_iso8601(date || ""),
         {rate, ""} <- Decimal.parse(value || ""),
         false <- Decimal.nan?(rate) or Decimal.inf?(rate),
         true <- Decimal.gt?(rate, 0) and not Decimal.gt?(rate, @max_rate) do
      [{currency, date, rate}]
    else
      _missing -> []
    end
  end
end

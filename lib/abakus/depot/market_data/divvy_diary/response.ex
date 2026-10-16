defmodule Abakus.Depot.MarketData.DivvyDiary.Response do
  @moduledoc """
  Reads DivvyDiary's answer for one ISIN (`GET /symbols/{isin}`). DivvyDiary does not document it;
  the format is assumed from a recorded answer in Portfolio Performance's tests
  (`divvy_diary_response_with_payments.json`):

  - `countryWeightings` and `sectorWeightings` are lists of `{"country": "US", "weight": 0.19}` and
    `{"sector": "Energy", "weight": 0.13}`; a map such as `{"US": 0.19}` is read too
  - countries are ISO 3166 alpha-2 codes, sectors GICS names in English
  - weights are fractions of 1, and the scale does not matter, see `Abakus.Depot.Allocation`
  - a share has empty lists, and its own `country` and `sector`, which are not read
  - `dividends` is a list of `{"exDate": "2024-02-21", "payDate": "2024-03-07", "amount": 0.5579,
    "currency": "EUR"}`, the amount per share in the currency of the dividend; the live API also
    marks DivvyDiary's own projections with `"forecast": true`, which PP's recording lacks
  """

  require Logger

  @doc "`composition/1` and `dividends/1` in one map."
  def symbol(json) do
    with {:ok, composition} <- composition(json),
         {:ok, dividends} <- dividends(json) do
      {:ok, %{composition: composition, dividends: dividends}}
    end
  end

  @doc """
  The composition as `%{countries: %{code => weight}, sectors: %{name => weight}}`; null counts as
  no weights, and a country or sector listed twice adds up.
  """
  def composition(%{"countryWeightings" => countries, "sectorWeightings" => sectors}) do
    with {:ok, countries} <- weights(countries, "country"),
         {:ok, sectors} <- weights(sectors, "sector") do
      {:ok, %{countries: countries, sectors: sectors}}
    end
  end

  def composition(_json), do: {:error, :invalid_response}

  defp weights(nil, _key), do: {:ok, %{}}
  defp weights(map, _key) when is_map(map), do: sum(Map.to_list(map))

  defp weights(list, key) when is_list(list), do: list |> Enum.map(&pair(&1, key)) |> sum()
  defp weights(_other, _key), do: {:error, :invalid_response}

  defp pair(%{"weight" => weight} = item, key), do: {item[key], weight}
  defp pair(_item, _key), do: :invalid

  defp sum(pairs) do
    if Enum.all?(pairs, &match?({name, weight} when is_binary(name) and is_number(weight), &1)),
      do:
        {:ok,
         Enum.reduce(pairs, %{}, fn {name, w}, acc -> Map.update(acc, name, w, &(&1 + w)) end)},
      else: {:error, :invalid_response}
  end

  @doc """
  The dividends as `%{ex_date: date | nil, pay_date: date, per_share: amount × 10⁸, currency:
  code}`. Forecasts and those without a pay date are left out, malformed ones too, with a warning.
  Missing or null counts as no dividends.
  """
  def dividends(%{"dividends" => list}) when is_list(list),
    do: {:ok, list |> Enum.reject(&left_out?/1) |> Enum.flat_map(&read_dividend/1)}

  def dividends(%{"dividends" => nil}), do: {:ok, []}
  def dividends(%{"dividends" => _other}), do: {:error, :invalid_response}
  def dividends(json) when is_map(json), do: {:ok, []}
  def dividends(_json), do: {:error, :invalid_response}

  defp left_out?(%{} = item), do: item["forecast"] not in [nil, false] or item["payDate"] == nil
  defp left_out?(_item), do: false

  defp read_dividend(item) do
    case dividend(item) do
      {:ok, dividend} ->
        [dividend]

      :error ->
        Logger.warning("Left out a malformed DivvyDiary dividend: #{inspect(item)}")
        []
    end
  end

  defp dividend(%{"payDate" => pay_date, "amount" => amount, "currency" => currency} = item)
       when is_number(amount) and amount > 0 and is_binary(currency) do
    with {:ok, pay_date} <- date(pay_date),
         {:ok, ex_date} <- optional_date(item["exDate"]) do
      {:ok,
       %{ex_date: ex_date, pay_date: pay_date, per_share: per_share(amount), currency: currency}}
    end
  end

  defp dividend(_item), do: :error

  defp optional_date(nil), do: {:ok, nil}
  defp optional_date(text), do: date(text)

  defp date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp date(_other), do: :error

  defp per_share(amount) when is_integer(amount), do: amount * 100_000_000

  defp per_share(amount) do
    amount
    |> Decimal.from_float()
    |> Decimal.mult(100_000_000)
    |> Decimal.round(0, :half_even)
    |> Decimal.to_integer()
  end
end

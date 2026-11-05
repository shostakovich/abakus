defmodule AbakusWeb.Depot.SecurityRow do
  @moduledoc "What a row of the securities page shows of a security, apart from its name."

  alias Abakus.Depot.Securities.Security
  alias Abakus.Format
  alias AbakusWeb.Depot.Format, as: DepotFormat

  @doc ~s(Where its prices come from, retired or not: `"Yahoo · VGWL.DE"` or `"Ohne Kursabruf"`.)
  def source(%Security{quote_feed: :yahoo, symbol: symbol}), do: "Yahoo⁠ · #{symbol}"
  def source(%Security{}), do: "Ohne Kursabruf"

  @doc ~s(Its source in short, for a row's sub-line: `"VGWL.DE"`, else as `source/1`.)
  def short_source(%Security{quote_feed: :yahoo, symbol: symbol}), do: symbol
  def short_source(%Security{} = security), do: source(security)

  @doc ~s(The date of its latest quote, without the year in the year of `today`: `"04.11."`.)
  def quote_date(%Security{latest_date: nil}, _today), do: nil

  def quote_date(%Security{latest_date: date}, today),
    do: Format.date(date, year: date.year != today.year)

  @doc "Its latest quote with the decimals it has; a dash without one."
  def price(%Security{} = security),
    do: DepotFormat.price(security.latest_close, security.currency)

  @doc """
  Its marks in this order: `{:error, message}` for each failed fetch, `:no_fund_data` when
  DivvyDiary does not know its ISIN, `:no_isin`, `:benchmark` when it is the user's
  (`benchmark_id`). DivvyDiary's only with its API key (`divvy_diary`). A retired security
  fetches nothing, so it shows no errors and needs no ISIN.
  """
  def marks(%Security{} = security, benchmark_id, divvy_diary) do
    fetching = !security.retired
    divvy_diary = fetching and divvy_diary and security.isin not in [nil, ""]

    errors =
      for message <- [
            fetching && yahoo_error(security),
            divvy_diary && security.divvy_diary_error
          ],
          is_binary(message),
          do: {:error, message}

    errors ++
      mark(divvy_diary and security.divvy_diary_unknown, :no_fund_data) ++
      mark(fetching and security.isin in [nil, ""], :no_isin) ++
      mark(security.id == benchmark_id, :benchmark)
  end

  defp mark(true, mark), do: [mark]
  defp mark(_shown, _mark), do: []

  defp yahoo_error(%Security{quote_feed: :yahoo, fetch_error: error}), do: error
  defp yahoo_error(%Security{}), do: nil
end

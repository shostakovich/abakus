defmodule AbakusWeb.Depot.AttributeValue do
  @moduledoc """
  An attribute of a security as the security page shows it, read as the converter of its PP
  attribute type stores it: `{:text, text}`, `{:link, label, url}` or `{:image, data_uri}`, nil
  for a value the page cannot show, such as a logo that is no embedded image.
  """

  alias Abakus.Depot.Securities.AttributeType
  alias Abakus.Money
  alias AbakusWeb.Depot.Format

  @converters "name.abuchen.portfolio.model.AttributeType$"
  @epoch ~D[1970-01-01]
  @operators %{"<" => "<", "<=" => "≤", ">" => ">", ">=" => "≥"}

  @doc "The value of an attribute of `type` of a security whose prices are in `currency`."
  def display(%AttributeType{converter: @converters <> converter}, value, currency),
    do: converted(converter, value, currency)

  def display(_type, value, _currency), do: plain(value)

  # A percentage is a fraction, a plain one is in percent already.
  defp converted("PercentConverter", value, _currency) when is_number(value),
    do: {:text, value |> decimal() |> Decimal.mult(100) |> Format.percent(2)}

  defp converted("PercentPlainConverter", value, _currency) when is_number(value),
    do: {:text, value |> decimal() |> Format.percent(2)}

  # Amounts in cents, without a currency.
  defp converted(amount, value, _currency)
       when amount in ["AmountConverter", "AmountPlainConverter"] and is_integer(value),
       do: {:text, Money.amount(value)}

  defp converted("QuoteConverter", value, currency) when is_integer(value),
    do: {:text, Format.price(value, currency)}

  defp converted("ShareConverter", value, _currency) when is_integer(value),
    do: {:text, Format.shares(value)}

  defp converted("DateConverter", value, _currency) when is_integer(value),
    do: {:text, @epoch |> Date.add(value) |> Format.date()}

  defp converted("LimitPriceConverter", value, currency) when is_binary(value),
    do: limit_price(value, currency)

  defp converted("BookmarkConverter", value, _currency) when is_binary(value),
    do: bookmark(value)

  defp converted("ImageConverter", "data:image/" <> _ = value, _currency), do: {:image, value}
  defp converted("ImageConverter", _value, _currency), do: nil
  defp converted(_converter, value, _currency), do: plain(value)

  # An operator and a price × 10⁸, e.g. `>=15000000000`.
  defp limit_price(value, currency) do
    case Regex.run(~r/^\s*(<=?|>=?)\s*(\d+)\s*$/, value) do
      [_, operator, price] ->
        {:text, "#{@operators[operator]} #{Format.price(String.to_integer(price), currency)}"}

      nil ->
        plain(value)
    end
  end

  # `[label](url)` or a plain URL; only a web address becomes a link.
  defp bookmark(value) do
    {label, url} =
      case Regex.run(~r/^\[([^\]]*)\]\(([^\s)]*)\)$/, String.trim(value)) do
        [_, "", url] -> {url, url}
        [_, label, url] -> {label, url}
        nil -> {value, String.trim(value)}
      end

    if url =~ ~r{^https?://\S+$}i, do: {:link, label, url}, else: {:text, label}
  end

  defp plain(value) when is_binary(value), do: {:text, value}
  defp plain(true), do: {:text, "ja"}
  defp plain(false), do: {:text, "nein"}
  defp plain(value) when is_number(value), do: {:text, to_string(value)}
  defp plain(_value), do: nil

  defp decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp decimal(value) when is_integer(value), do: Decimal.new(value)
end

defmodule AbakusWeb.Format do
  @moduledoc "Amounts, dates and months as the German UI shows and reads them; amounts are integer cents."

  @months ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)

  # "1.234,56" or "12,5" (a dot only between groups of three); else a dot before the cents, "12.5". A separator
  # without cents ("12,") stands for whole euros.
  @german ~r/^([+-]?)(\d{1,3}(?:\.\d{3})+|\d*)(?:,(\d{0,2}))?$/
  @dotted ~r/^([+-]?)(\d*)\.(\d{0,2})$/
  @max_length 30

  @doc ~S|Cents as "1.234,56", negative with a real minus sign: "−9,99".|
  def amount(cents) when is_integer(cents) do
    rest = cents |> abs() |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{if cents < 0, do: "−"}#{cents |> abs() |> div(100) |> count()},#{rest}"
  end

  @doc ~S|A count of things with a dot between groups of three: "1.842".|
  def count(number) when is_integer(number) and number >= 0,
    do: Regex.replace(~r/\B(?=(\d{3})+$)/, Integer.to_string(number), ".")

  def euros(cents), do: amount(cents) <> " €"

  @doc ~S|Euros with a plus for inflows: "+48,75 €", "−9,99 €".|
  def signed_euros(cents) when cents > 0, do: "+" <> euros(cents)
  def signed_euros(cents), do: euros(cents)

  @doc """
  Reads an amount typed in German ("1.234,56", "12,5", "−5") or with a decimal dot ("12.50") into cents; empty is
  zero. Anything else, more than two decimals included, is `:error`.
  """
  def parse_amount(text) when is_binary(text) do
    text = text |> String.replace(~r/[\s€]/u, "") |> String.replace("−", "-")

    cond do
      text == "" -> {:ok, 0}
      String.length(text) > @max_length -> :error
      true -> cents(Regex.run(@german, text) || Regex.run(@dotted, text))
    end
  end

  defp cents([_, sign, euros]) when euros != "", do: cents([nil, sign, euros, ""])

  defp cents([_, sign, euros, fraction]) when euros != "" or fraction != "" do
    value =
      digits(String.replace(euros, ".", "")) * 100 + digits(String.pad_trailing(fraction, 2, "0"))

    {:ok, if(sign == "-", do: -value, else: value)}
  end

  defp cents(_no_match), do: :error

  defp digits(""), do: 0
  defp digits(digits), do: String.to_integer(digits)

  @doc ~S|"07.03.2026"|
  def date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")

  @doc ~S|"07.03.", the date without its year.|
  def day(%Date{} = date), do: Calendar.strftime(date, "%d.%m.")

  @doc ~S|"1. Juni 2027"|
  def long_date(%Date{year: year} = date), do: "#{day_month(date)} #{year}"

  @doc ~S|"24. Dezember", the written-out date without its year.|
  def day_month(%Date{day: day} = date), do: "#{day}. #{month_name(date)}"

  @doc "The browser's date (ISO 8601), as long as it is a plausible one; else today in UTC."
  def today(param) do
    case is_binary(param) && Date.from_iso8601(param) do
      {:ok, %Date{year: year} = date} when year in 2000..2099 -> date
      _ -> Date.utc_today()
    end
  end

  def month_name(%Date{month: month}), do: Enum.at(@months, month - 1)

  def month_short(date), do: date |> month_name() |> String.slice(0, 3)

  def month_year(%Date{year: year} = date), do: "#{month_name(date)} #{year}"
end

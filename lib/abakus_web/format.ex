defmodule AbakusWeb.Format do
  @moduledoc "Counts, dates and months as the German UI shows and reads them; amounts are `Abakus.Money`'s."

  @months ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)

  @doc ~S|A count of things with a dot between groups of three: "1.842".|
  def count(number) when is_integer(number) and number >= 0,
    do: Regex.replace(~r/\B(?=(\d{3})+$)/, Integer.to_string(number), ".")

  @doc ~S|"07.03.2026"|
  def date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")

  @doc ~S|"07.03.", the date without its year.|
  def day(%Date{} = date), do: Calendar.strftime(date, "%d.%m.")

  @doc ~S|"1. Juni 2027"|
  def long_date(%Date{year: year} = date), do: "#{day_month(date)} #{year}"

  @doc ~S|"24. Dezember", the written-out date without its year.|
  def day_month(%Date{day: day} = date), do: "#{day}. #{month_name(date)}"

  def month_name(%Date{month: month}), do: Enum.at(@months, month - 1)

  def month_short(date), do: date |> month_name() |> String.slice(0, 3)

  def month_year(%Date{year: year} = date), do: "#{month_name(date)} #{year}"
end

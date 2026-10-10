defmodule AbakusWeb.BudgetLive.Window do
  @moduledoc """
  The months the budget shows: as many as fit from the first one (`months`), between the budget's first month and
  five years after the current one. The focus month is the chosen one, else the current, else the first, as long
  as it is shown. The strip lists `span` months around them, up to the last month that can be shown; a month starting
  the strip or a year carries the year.
  Months are their first day.
  """

  defstruct [:first, :focus, months: [], strip: [], earlier: false, later: false]

  @ahead 60

  @doc "Options: `months` (how many fit), `span` (strip length), `focus` (the chosen month or nil)."
  def new(requested, earliest, current, opts) do
    first = requested |> at_most(latest(current)) |> at_least(earliest)
    months = Enum.map(0..(opts[:months] - 1), &shift(first, &1))
    focus = Enum.find([opts[:focus], current, first], &(&1 in months))

    %__MODULE__{
      first: first,
      months: months,
      focus: focus,
      strip: strip(months, focus, current, earliest, opts[:span]),
      earlier: Date.after?(first, earliest),
      later: Date.before?(first, latest(current))
    }
  end

  @doc "The last month the budget has to compute so that `new/4` finds every month it may show."
  def through(requested, current, months) do
    requested |> at_most(latest(current)) |> at_least(current) |> shift(months - 1)
  end

  @doc "A month as the URL has it: \"2026-10\"."
  def param(%Date{} = month), do: Calendar.strftime(month, "%Y-%m")

  def parse_param(param) when is_binary(param) do
    with [_, year, month] <- Regex.run(~r/^(\d{4})-(\d{2})$/, param),
         {:ok, date} <- Date.new(String.to_integer(year), String.to_integer(month), 1) do
      {:ok, date}
    else
      _ -> :error
    end
  end

  def parse_param(_param), do: :error

  defp strip(months, focus, current, earliest, span) do
    last = current |> latest() |> shift(length(months) - span)

    from =
      months
      |> hd()
      |> shift(-div(span - length(months), 2))
      |> at_most(last)
      |> at_least(earliest)

    Enum.map(0..(span - 1), fn offset ->
      month = shift(from, offset)

      %{
        month: month,
        visible: month in months,
        focus: month == focus,
        current: month == current,
        year: if(offset == 0 or month.month == 1, do: month.year)
      }
    end)
  end

  defp latest(current), do: shift(current, @ahead)

  defp shift(month, by), do: Date.shift(month, month: by)

  defp at_least(month, earliest), do: Enum.max([month, earliest], Date)
  defp at_most(month, latest), do: Enum.min([month, latest], Date)
end

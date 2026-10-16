defmodule Abakus.Depot.Performance.IRR do
  @moduledoc """
  The internal rate of return of dated cash flows over years of 365 days (XIRR), solved as PP's
  `IRR` does (read, not copied), so that the result matches PP's to its last digits: it seeks
  1 + rate, starting from a guess found by halving (0, 1) when the last cash flow and the sum of
  all have different signs and from 1.05 otherwise, then takes Newton's steps with a numerical
  derivative until a step is smaller than 0.00001, at most 500 of them.
  """

  @stop 0.00001
  @steps 500

  @doc """
  The annual rate at which `cash_flows`, `{date, amount}` in order of date with money paid in
  negative, add up to nothing on the first date; nil where PP gets no number.
  """
  def calculate([_ | _] = cash_flows) do
    npv = net_present_value(cash_flows)
    amounts = Enum.map(cash_flows, &elem(&1, 1))

    npv |> seek(guess(npv, List.last(amounts), Enum.sum(amounts))) |> Kernel.-(1)
  rescue
    # Floats on the BEAM have no NaN or infinity: where PP's doubles become them, this raises.
    ArithmeticError -> nil
  end

  defp net_present_value([{first, _amount} | _] = cash_flows) do
    terms =
      Enum.map(cash_flows, fn {date, amount} -> {Date.diff(date, first) / 365.0, amount} end)

    fn factor ->
      Enum.reduce(terms, 0.0, fn {years, amount}, sum ->
        sum + amount / :math.pow(factor, years)
      end)
    end
  end

  # Close to 0 the present value takes the sign of the last cash flow, at 1 that of their sum.
  defp guess(npv, at_zero, at_one) do
    if sign(at_zero) == sign(at_one), do: 1.05, else: halve(npv, 0.0, 1.0, at_zero, at_one)
  end

  defp halve(npv, left, right, at_left, at_right) do
    center = (left + right) / 2

    if right - left < 0.001 do
      center
    else
      at_center = npv.(center)

      cond do
        at_center == 0 -> center
        sign(at_center) == sign(at_right) -> halve(npv, left, center, at_left, at_center)
        true -> halve(npv, center, right, at_center, at_right)
      end
    end
  end

  defp seek(npv, guess) do
    Enum.reduce_while(1..@steps, guess, fn _step, x ->
      next = x - npv.(x) / derivative(npv, x)
      if abs(next - x) > @stop, do: {:cont, next}, else: {:halt, next}
    end)
  end

  defp derivative(npv, x) do
    delta = abs(x) / 1.0e6
    (npv.(x + delta) - npv.(x - delta)) / (2 * delta)
  end

  defp sign(x) when x > 0, do: 1
  defp sign(x) when x < 0, do: -1
  defp sign(_zero), do: 0
end

defmodule AbakusWeb.BudgetLive.WindowTest do
  use ExUnit.Case, async: true

  alias AbakusWeb.BudgetLive.Window

  @current ~D[2026-10-01]
  @earliest ~D[2025-01-01]

  defp window(requested, opts \\ []) do
    Window.new(requested, @earliest, @current,
      months: Keyword.get(opts, :months, 3),
      span: Keyword.get(opts, :span, 12),
      focus: Keyword.get(opts, :focus)
    )
  end

  describe "new/4" do
    test "shows as many months as fit from the first one" do
      assert %Window{
               first: ~D[2026-10-01],
               months: [~D[2026-10-01], ~D[2026-11-01], ~D[2026-12-01]]
             } =
               window(~D[2026-10-01])

      assert window(~D[2026-12-01], months: 1).months == [~D[2026-12-01]]
    end

    test "starts no earlier than the budget and no later than five years ahead" do
      assert window(~D[2020-03-01]).first == @earliest
      assert window(~D[2040-01-01]).first == ~D[2031-10-01]
    end

    test "the focus is the chosen month, else the current one, else the first, while it is shown" do
      assert window(~D[2026-10-01], focus: ~D[2026-11-01]).focus == ~D[2026-11-01]
      assert window(~D[2026-09-01]).focus == @current
      assert window(~D[2026-09-01], focus: ~D[2026-12-01]).focus == @current
      assert window(~D[2027-01-01], focus: ~D[2026-10-01]).focus == ~D[2027-01-01]
    end

    test "the strip shows `span` months around the visible ones, with a year at its start and in January" do
      strip = window(~D[2026-10-01], span: 7).strip

      assert Enum.map(strip, & &1.month) ==
               Enum.map(7..13, &Date.shift(~D[2026-01-01], month: &1))

      assert [
               %{year: 2026},
               _,
               %{month: ~D[2026-10-01], visible: true, focus: true, current: true} | _
             ] =
               strip

      assert %{month: ~D[2027-01-01], year: 2027, visible: false} = Enum.at(strip, 5)
      assert Enum.count(strip, & &1.year) == 2

      assert Enum.map(Enum.filter(strip, & &1.visible), & &1.month) ==
               window(~D[2026-10-01]).months
    end

    test "the strip begins no earlier than the budget" do
      assert hd(window(@earliest, span: 7).strip).month == @earliest
    end

    test "the strip ends with the last month that can be shown" do
      strip = window(~D[2031-10-01], span: 12).strip
      assert List.last(strip).month == ~D[2031-12-01]
      assert length(strip) == 12
    end

    test "knows whether the months can move earlier or later" do
      assert %Window{earlier: false, later: true} = window(@earliest)
      assert %Window{earlier: true, later: false} = window(~D[2031-10-01])
    end
  end

  test "through/3 is the last month the budget has to compute for a request" do
    assert Window.through(~D[2026-12-01], @current, 3) == ~D[2027-02-01]
    assert Window.through(~D[2020-01-01], @current, 2) == ~D[2026-11-01]
    assert Window.through(~D[2040-01-01], @current, 1) == ~D[2031-10-01]
  end

  test "a month is \"2026-10\" in the URL; anything else is no month" do
    assert Window.param(~D[2026-10-01]) == "2026-10"
    assert Window.parse_param("2026-03") == {:ok, ~D[2026-03-01]}

    for param <- [nil, "2026-13", "2026-3", "26-03", "2026-03-01", "heute"],
        do: assert(Window.parse_param(param) == :error, inspect(param))
  end
end

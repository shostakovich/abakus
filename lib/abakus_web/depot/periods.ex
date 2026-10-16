defmodule AbakusWeb.Depot.Periods do
  @moduledoc """
  The periods a page offers in its `<.segmented>` „Zeitraum“, each as `{param, period, label,
  long_label}`: the URL parameter, the period, the button label and its accessible name.
  """

  @doc "The period of the URL parameter `param`, `default` for any other."
  def parse(periods, param, default),
    do:
      Enum.find_value(periods, default, fn {p, period, _label, _long} -> p == param && period end)

  @doc "The URL parameter of `period`."
  def param(periods, period),
    do: Enum.find_value(periods, fn {param, p, _label, _long} -> p == period && param end)

  @doc "The button label of `period`."
  def label(periods, period),
    do: Enum.find_value(periods, fn {_param, p, label, _long} -> p == period && label end)

  @doc "The options of `<.segmented>`, each linking to `path.(period)`."
  def options(periods, path) do
    for {_param, period, label, long} <- periods,
        do: %{label: label, long_label: long, value: period, path: path.(period)}
  end
end

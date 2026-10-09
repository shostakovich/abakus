defmodule Abakus.YnabImport.Report do
  @moduledoc "What an import did and how its numbers compare with YNAB's (`Abakus.YnabImport.Check`)."

  alias Abakus.YnabImport.Plan

  defstruct [:plan, counts: %{}, merged_payees: [], differences: []]

  @doc "The report as lines for the operator."
  def lines(%__MODULE__{} = report) do
    [imported(report)] ++ Enum.map(report.merged_payees, &merged/1) ++ check(report.differences)
  end

  defp imported(%{plan: plan, counts: counts}) do
    "Imported “#{plan}”: #{counts.accounts} accounts, #{counts.categories} categories, " <>
      "#{counts.payees} payees, #{counts.transactions} transactions."
  end

  defp merged({name, others}),
    do:
      "Merged payees with the same name: “#{name}” takes in #{Enum.map_join(others, ", ", &"“#{&1}”")}."

  defp check([]), do: ["Every month, category and account matches YNAB."]

  defp check(differences) do
    count = length(differences)

    ["#{count} #{if count == 1, do: "difference", else: "differences"} from YNAB:"] ++
      Enum.map(differences, fn %{where: where, field: field, ynab: ynab, abakus: abakus} ->
        "  #{where}, #{field}: YNAB #{Plan.format(ynab)}, Abakus #{Plan.format(abakus)}"
      end)
  end
end

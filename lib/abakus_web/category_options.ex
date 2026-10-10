defmodule AbakusWeb.CategoryOptions do
  @moduledoc """
  Categories as the category pickers offer them, in groups: Ready to Assign first as income, then the categories
  by group, each with what it has available in the month of `today`, as YNAB shows them. An option's `text` is how
  the register names the category, `key` its lookup key.
  """

  alias Abakus.{Budget, Categories, Names}

  def build(%Date{} = today) do
    ready_to_assign = Categories.ready_to_assign!()
    month = month(today)
    available = Map.new(month.categories, &{&1.category_id, &1.available})

    groups =
      for %{categories: [_ | _] = categories} = group <- Categories.list_category_groups() do
        %{
          name: group.name,
          options:
            Enum.map(categories, fn category ->
              option(category.id, category.name, text(group.name, category.name), available)
            end)
        }
      end

    income = %{
      option(ready_to_assign.id, "Zu verteilen", "Einnahme: Zu verteilen", %{})
      | available: month.ready_to_assign_shown
    }

    [%{name: "Einnahme", options: [income]} | groups]
  end

  defp month(today) do
    month = Date.beginning_of_month(today)
    Categories.budget() |> Budget.months(today) |> Enum.find(&(&1.month == month))
  end

  defp option(id, name, text, available),
    do: %{
      id: id,
      name: name,
      text: text,
      key: Names.lookup_key(name),
      available: Map.get(available, id, 0)
    }

  @doc ~S|How the register names a category: "Wohnen: Miete", the group without its emoji.|
  def text(group_name, name), do: "#{elem(Names.split_emoji(group_name), 1)}: #{name}"

  @doc "The category ids among the options."
  def ids(groups), do: Enum.flat_map(groups, fn group -> Enum.map(group.options, & &1.id) end)

  @doc "The option with the id, nil when there is none."
  def find(groups, id) do
    Enum.find_value(groups, fn group -> Enum.find(group.options, &(&1.id == id)) end)
  end
end

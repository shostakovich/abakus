defmodule Abakus.DomainFixtures do
  @moduledoc "Category groups and categories for tests."

  alias Abakus.Categories

  def unique_name(prefix), do: "#{prefix} #{System.unique_integer([:positive])}"

  def category_group_fixture(attrs \\ %{}) do
    {:ok, group} =
      attrs |> Enum.into(%{name: unique_name("Gruppe")}) |> Categories.create_category_group()

    group
  end

  def category_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: unique_name("Kategorie")})
    attrs = Map.put_new_lazy(attrs, :category_group_id, fn -> category_group_fixture().id end)
    {:ok, category} = Categories.create_category(attrs)
    category
  end
end

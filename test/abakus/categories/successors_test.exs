defmodule Abakus.Categories.SuccessorsTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ids, Sync}
  alias Abakus.Categories.Category

  @november ~D[2026-11-01]

  setup do
    fix_now(~U[2026-11-02 11:00:00Z])
    group = category_group_fixture()
    one = fn name -> category_fixture(name: name, category_group_id: group.id) end
    %{scope: budget_scope(), magazines: one.("Zeitschriften"), books: one.("Bücher")}
  end

  defp assigned(scope, category),
    do: Map.get(Categories.budget(scope).assigned, {category.id, @november}, 0)

  defp late_assignment(scope, category, amount) do
    id = Ids.assignment(category.id, @november)
    clock = "2026-11-02T10:05:00.000Z-0000-mac"

    {:ok, 3} =
      Sync.apply_messages(
        scope,
        "mac",
        for {column, value} <- [category_id: category.id, month: "2026-11-01", amount: amount] do
          %{
            "table" => "assignments",
            "row_id" => id,
            "column" => to_string(column),
            "value" => value,
            "clock" => clock
          }
        end
      )
  end

  test "follow chains, and a cycle ends at its smallest id", c do
    papers = category_fixture()
    {:ok, _} = Categories.delete_category(c.scope, c.magazines, papers)
    {:ok, _} = Categories.delete_category(c.scope, papers, c.books)

    assert Categories.successors(c.scope) == %{
             c.magazines.id => c.books.id,
             papers.id => c.books.id
           }

    Repo.update_all(from(k in Category, where: k.id == ^c.books.id),
      set: [deleted_at: DateTime.utc_now(), successor_id: c.magazines.id]
    )

    smallest = Enum.min([c.magazines.id, papers.id, c.books.id])
    assert Categories.successors(c.scope) |> Map.values() |> Enum.uniq() == [smallest]
  end

  test "an assignment that reaches a deleted category counts for its successor", c do
    {:ok, _} = Categories.assign(c.scope, c.books, @november, 2_000)
    {:ok, _} = Categories.delete_category(c.scope, c.magazines, c.books)
    late_assignment(c.scope, c.magazines, 500)

    assert assigned(c.scope, c.books) == 2_500

    {:ok, _} = Categories.assign(c.scope, c.books, @november, 3_000)
    assert assigned(c.scope, c.books) == 3_000

    {:ok, 1_000} = Categories.move_assigned(c.scope, :ready_to_assign, c.books, @november, 1_000)
    assert assigned(c.scope, c.books) == 4_000

    :ok = Categories.reset_assignments(c.scope, @november, c.books)
    assert assigned(c.scope, c.books) == 0
  end
end

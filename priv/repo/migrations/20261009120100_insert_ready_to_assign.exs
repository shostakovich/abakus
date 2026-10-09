defmodule Abakus.Repo.Migrations.InsertReadyToAssign do
  use Ecto.Migration

  @now "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"

  # YNAB's internal group and category for income, under YNAB's names.
  def change do
    execute(
      """
      INSERT INTO category_groups (name, hidden, internal, position, inserted_at, updated_at)
      VALUES ('Internal Master Category', false, true, 0, #{@now}, #{@now})
      """,
      "DELETE FROM category_groups WHERE internal"
    )

    execute(
      """
      INSERT INTO categories
        (category_group_id, name, lookup_key, hidden, internal, position, inserted_at, updated_at)
      SELECT id, 'Inflow: Ready to Assign', 'inflow: ready to assign', false, true, 0, #{@now}, #{@now}
      FROM category_groups WHERE internal
      """,
      "DELETE FROM categories WHERE internal"
    )
  end
end

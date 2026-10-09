defmodule Abakus.SchemaTest do
  use ExUnit.Case, async: true

  defmodule Entry do
    @moduledoc false
    use Abakus.Schema

    schema "entries" do
      timestamps()
    end
  end

  test "migrations create timestamp columns of the type the schemas use" do
    migration_type = Abakus.Repo.config()[:migration_timestamps][:type]

    assert migration_type == Entry.__schema__(:type, :inserted_at)
    assert migration_type == Entry.__schema__(:type, :updated_at)
  end
end

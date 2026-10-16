defmodule Abakus.Depot.Taxonomies do
  @moduledoc "A user's taxonomies with classifications, target weights and assignments."

  import Ecto.Query, warn: false

  alias Abakus.Depot.Taxonomies.{Classification, Taxonomy}
  alias Abakus.Repo
  alias Abakus.Users.Scope

  def list_taxonomies(%Scope{} = scope) do
    classifications = from c in Classification, order_by: [c.rank, c.id], preload: :assignments

    Repo.all(
      from t in Taxonomy,
        where: t.user_id == ^scope.user.id,
        order_by: t.name,
        preload: [classifications: ^classifications]
    )
  end
end

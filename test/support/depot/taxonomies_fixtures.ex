defmodule Abakus.Depot.TaxonomiesFixtures do
  @moduledoc "Taxonomies, classifications and assignments for tests; weights in 1/100 percent."

  alias Abakus.Depot.Portfolios.Account
  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Taxonomies.{Assignment, Classification, Taxonomy}
  alias Abakus.Repo
  alias Abakus.Users.Scope

  @doc "A taxonomy of the user and its root classification, as PP keeps it."
  def taxonomy_fixture(%Scope{user: user}, name \\ "Anlageklassen") do
    taxonomy = Repo.insert!(%Taxonomy{user_id: user.id, name: name})
    root = Repo.insert!(%Classification{taxonomy_id: taxonomy.id, name: name, weight: 10_000})
    {taxonomy, root}
  end

  @doc "A classification below `parent` with its target weight."
  def classification_fixture(%Classification{} = parent, name, weight, rank \\ 0) do
    Repo.insert!(%Classification{
      taxonomy_id: parent.taxonomy_id,
      parent_id: parent.id,
      name: name,
      weight: weight,
      rank: rank
    })
  end

  @doc "Puts a security or an account into the classification with `weight`."
  def assignment_fixture(classification, vehicle, weight \\ 10_000)

  def assignment_fixture(%Classification{id: id}, %Security{} = security, weight),
    do: Repo.insert!(%Assignment{classification_id: id, security_id: security.id, weight: weight})

  def assignment_fixture(%Classification{id: id}, %Account{} = account, weight),
    do: Repo.insert!(%Assignment{classification_id: id, account_id: account.id, weight: weight})
end

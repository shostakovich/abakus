defmodule Abakus.Depot.BudgetLink do
  @moduledoc """
  The budget owner's Depot linked to the budget (ADR 0020): from its start date on, the cash side of their Depot
  transactions in budget accounts is booked too, purchases in its category (`Abakus.Depot.CashSide`).
  """

  import Ecto.Query

  alias Abakus.Categories
  alias Abakus.Categories.Category
  alias Abakus.Depot.BudgetLink.Link
  alias Abakus.Depot.CashSide
  alias Abakus.{LocalTime, Repo}
  alias Abakus.Users.{Scope, User}
  alias Ecto.Changeset

  @doc "The user's link, nil while it is off."
  def get(%Scope{user: %User{id: id}}), do: Repo.get(Link, id)

  @doc "A changeset for switching the link on, starting today."
  def change_link(attrs \\ %{}),
    do: Link.changeset(%Link{start_date: LocalTime.today()}, attrs)

  @doc "The user's regular budget categories purchases can be booked in, grouped for a select."
  def category_options(%Scope{} = scope) do
    for %{categories: [_ | _] = categories} = group <- Categories.list_category_groups(scope),
        do: {group.name, Enum.map(categories, &{&1.name, &1.id})}
  end

  @doc """
  Switches the link on for the budget owner with `category_id` and `start_date`, and books the cash side of their
  Depot transactions since then in budget accounts. Returns `{:ok, link}`, `{:error, changeset}`,
  `{:error, :not_budget_owner}`, `{:error, :linked}` or `{:error, message}` when a transaction cannot be written.
  """
  def switch_on(%Scope{} = scope, attrs) do
    if Scope.budget_owner?(scope),
      do: Repo.transact(fn -> link(scope, attrs) end),
      else: {:error, :not_budget_owner}
  end

  defp link(%Scope{user: user} = scope, attrs) do
    with :ok <- if(Repo.get(Link, user.id), do: {:error, :linked}, else: :ok),
         {:ok, link} <-
           %Link{user_id: user.id}
           |> Link.changeset(attrs)
           |> validate_category()
           |> Repo.insert(),
         :ok <- CashSide.sync(scope) do
      {:ok, link}
    end
  end

  @doc """
  Changes the category of the user's later purchases; linked transactions keep theirs. Returns `{:ok, link}`,
  `{:error, changeset}` or `{:error, :not_linked}`.
  """
  def change_category(%Scope{} = scope, category_id) do
    case get(scope) do
      nil ->
        {:error, :not_linked}

      link ->
        link
        |> Link.changeset(%{category_id: category_id})
        |> validate_category()
        |> Repo.update()
    end
  end

  defp validate_category(%Changeset{data: %Link{user_id: user_id}} = changeset) do
    Changeset.validate_change(changeset, :category_id, fn :category_id, id ->
      if Repo.exists?(
           from c in Category, where: c.id == ^id and c.user_id == ^user_id and not c.internal
         ),
         do: [],
         else: [category_id: "ist keine Kategorie des Budgets"]
    end)
  end

  @doc "Moves the user's link's category from one budget category to another, as deleting `from_id` does."
  def recategorize(%Scope{user: %User{id: user_id}}, from_id, to_id) do
    Repo.update_all(where(Link, user_id: ^user_id, category_id: ^from_id),
      set: [category_id: to_id]
    )

    :ok
  end
end

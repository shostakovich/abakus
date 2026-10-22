defmodule Abakus.DomainFixtures do
  @moduledoc "Accounts, payees, categories and transactions for tests."

  alias Abakus.{Categories, Ledger, Repo, UsersFixtures}
  alias Abakus.Users.{Scope, User}

  def unique_name(prefix), do: "#{prefix} #{System.unique_integer([:positive])}"

  @doc "The budget owner's scope; without any user, the first one is created and owns the budget."
  def budget_scope,
    do: Scope.for_user(Repo.get_by(User, budget_owner: true) || UsersFixtures.user_fixture())

  def account_fixture(attrs \\ %{}) do
    {:ok, account} =
      Ledger.create_account(
        budget_scope(),
        Enum.into(attrs, %{name: unique_name("Konto"), kind: :checking})
      )

    account
  end

  def payee_fixture(attrs \\ %{}) do
    {:ok, payee} =
      Ledger.create_payee(budget_scope(), Enum.into(attrs, %{name: unique_name("Händler")}))

    payee
  end

  def category_group_fixture(attrs \\ %{}) do
    {:ok, group} =
      Categories.create_category_group(
        budget_scope(),
        Enum.into(attrs, %{name: unique_name("Gruppe")})
      )

    group
  end

  def category_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: unique_name("Kategorie")})
    attrs = Map.put_new_lazy(attrs, :category_group_id, fn -> category_group_fixture().id end)
    {:ok, category} = Categories.create_category(budget_scope(), attrs)
    category
  end

  def transaction_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{date: ~D[2026-10-09], amount: -1_250})
      |> Map.put_new_lazy(:account_id, fn -> account_fixture().id end)

    {:ok, transaction} = Ledger.create_transaction(budget_scope(), attrs)
    transaction
  end
end

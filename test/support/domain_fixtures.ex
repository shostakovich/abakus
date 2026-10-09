defmodule Abakus.DomainFixtures do
  @moduledoc "Accounts, payees, categories and transactions for tests."

  alias Abakus.{Categories, Ledger}

  def unique_name(prefix), do: "#{prefix} #{System.unique_integer([:positive])}"

  def account_fixture(attrs \\ %{}) do
    {:ok, account} =
      attrs
      |> Enum.into(%{name: unique_name("Konto"), kind: :checking})
      |> Ledger.create_account()

    account
  end

  def payee_fixture(attrs \\ %{}) do
    {:ok, payee} = attrs |> Enum.into(%{name: unique_name("Händler")}) |> Ledger.create_payee()
    payee
  end

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

  def transaction_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{date: ~D[2026-10-09], amount: -1_250})
      |> Map.put_new_lazy(:account_id, fn -> account_fixture().id end)

    {:ok, transaction} = Ledger.create_transaction(attrs)
    transaction
  end
end

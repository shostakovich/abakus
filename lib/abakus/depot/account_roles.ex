defmodule Abakus.Depot.AccountRoles do
  @moduledoc """
  The role of each Verrechnungskonto (ADR 0017), see `Account.role/1`: the same bank account as a budget account,
  for the budget owner, at most one per budget account; the cash of one of the user's portfolios, which
  counts toward that portfolio's value; or none. One without a role set shows as a warning on Vermögen.
  """

  import Ecto.Query

  alias Abakus.Depot.BudgetLink
  alias Abakus.Depot.Portfolios.{Account, Portfolio}
  alias Abakus.Ledger
  alias Abakus.Repo
  alias Abakus.Users.Scope

  @doc "The user's Verrechnungskonten not retired, by name, with the budget account or portfolio of their role."
  def list_accounts(%Scope{} = scope) do
    Repo.all(
      from a in Account,
        where: a.user_id == ^scope.user.id and not a.retired,
        order_by: [a.name, a.id],
        preload: [:budget_account, :cash_of_portfolio]
    )
  end

  @doc "The user's Verrechnungskonten without a role set, retired ones left out, by name."
  def without_role(%Scope{} = scope) do
    Repo.all(
      from a in Account,
        where:
          a.user_id == ^scope.user.id and not a.retired and is_nil(a.budget_account_id) and
            is_nil(a.cash_of_portfolio_id) and not a.no_role,
        order_by: [a.name, a.id]
    )
  end

  @doc "The ids of the Verrechnungskonten that are the cash of `portfolio`."
  def cash_account_ids(%Portfolio{id: id}),
    do:
      Repo.all(
        from a in Account, where: a.cash_of_portfolio_id == ^id, select: a.id, order_by: a.id
      )

  @doc """
  What `account` can be: `budget_accounts`, the open budget accounts in their order that nothing else feeds and no
  other Verrechnungskonto is, none unless the user owns the budget; `portfolios`, the
  user's active portfolios by name and the one it is the cash of.
  """
  def choices(%Scope{} = scope, %Account{} = account) do
    %{
      budget_accounts: budget_account_choices(scope, account),
      portfolios: portfolio_choices(scope, account)
    }
  end

  defp budget_account_choices(%Scope{} = scope, %Account{} = account) do
    if Scope.budget_owner?(scope), do: open_budget_accounts(scope, account), else: []
  end

  defp open_budget_accounts(scope, account) do
    taken =
      from a in Account,
        where: a.id != ^account.id and not is_nil(a.budget_account_id),
        select: a.budget_account_id

    Repo.all(
      from a in Ledger.Account,
        where:
          a.user_id == ^scope.user.id and a.kind in ^Ledger.Account.budget_kinds() and
            not a.closed and is_nil(a.fed_by) and a.id not in subquery(taken),
        order_by: [a.position, a.id]
    )
  end

  defp portfolio_choices(scope, account) do
    Repo.all(
      from p in Portfolio,
        where:
          p.user_id == ^scope.user.id and
            (not p.retired or p.id == ^(account.cash_of_portfolio_id || 0)),
        order_by: [p.name, p.id]
    )
  end

  @doc """
  Sets the role of a Verrechnungskonto of the user, given as `"budget_account:<id>"`, `"portfolio_cash:<id>"` or
  `"none"`. Returns `{:ok, account}` or `{:error, message}`.
  """
  def set_role(%Scope{} = scope, %Account{user_id: user_id} = account, param)
      when user_id == scope.user.id do
    with {:ok, role} <- parse(param),
         :ok <- check(scope, account, role) do
      Repo.transact(fn -> save_role(scope, account, role) end)
    end
  end

  defp save_role(scope, account, role) do
    case account |> Account.role_changeset(role) |> Repo.update() do
      {:ok, account} ->
        with :ok <- BudgetLink.sync(scope), do: {:ok, account}

      {:error, changeset} ->
        {:error, first_error(changeset)}
    end
  end

  @doc "A role as `set_role/3` takes it, nil for none set."
  def param({kind, id}), do: "#{kind}:#{id}"
  def param(:none), do: "none"
  def param(nil), do: nil

  defp parse("none"), do: {:ok, :none}
  defp parse("budget_account:" <> id), do: with_id(:budget_account, id)
  defp parse("portfolio_cash:" <> id), do: with_id(:portfolio_cash, id)
  defp parse(_param), do: {:error, "Wähle eine Rolle."}

  defp with_id(kind, id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, {kind, id}}
      _other -> parse(nil)
    end
  end

  defp check(scope, _account, {:budget_account, id}) do
    if Scope.budget_owner?(scope),
      do: check_budget_account(scope, id),
      else: {:error, "Nur wer das Budget führt, kann ein Budgetkonto wählen."}
  end

  defp check(scope, account, {:portfolio_cash, id}) do
    if Repo.exists?(
         from p in Portfolio,
           where:
             p.id == ^id and p.user_id == ^scope.user.id and
               (not p.retired or p.id == ^(account.cash_of_portfolio_id || 0))
       ),
       do: :ok,
       else: {:error, "Das ist keins deiner Depots."}
  end

  defp check(_scope, _account, :none), do: :ok

  defp check_budget_account(scope, id) do
    case Ledger.get_account(scope, id) do
      %Ledger.Account{closed: false, fed_by: nil} = budget_account ->
        if Ledger.Account.budget_account?(budget_account),
          do: :ok,
          else: {:error, "Das ist kein offenes Budgetkonto."}

      _other ->
        {:error, "Das ist kein offenes Budgetkonto."}
    end
  end

  defp first_error(%Ecto.Changeset{errors: [{_field, {message, _opts}} | _rest]}), do: message
end

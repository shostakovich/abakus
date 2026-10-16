defmodule AbakusWeb.AccountGroups do
  @moduledoc """
  Accounts as the sidebar and the account list group them: open budget accounts, open tracking accounts, then the
  closed ones, each account with its working and cleared balance and how many of its transactions wait for approval,
  each group with its working balance. Empty groups are left out.
  """

  alias Abakus.Ledger
  alias Abakus.Ledger.Account
  alias Abakus.Users.Scope
  alias AbakusWeb.Areas

  @no_transactions %{balance: 0, cleared: 0, unapproved: 0}
  @kinds [checking: "Girokonto", savings: "Sparkonto", cash: "Bargeld", tracking: "Tracking"]

  @doc "The kinds of accounts with their German names, in the order the form offers them."
  def kinds, do: @kinds

  def kind_label(kind), do: @kinds[kind]

  @doc "Assigns `account_groups` for the sidebar of every signed-in page; none for a user without the Budget."
  def on_mount(:assign, _params, _session, socket) do
    scope = socket.assigns.current_scope
    groups = if Areas.allowed?(scope, :budget), do: load(scope), else: []
    {:cont, Phoenix.Component.assign(socket, :account_groups, groups)}
  end

  def load(%Scope{} = scope), do: build(Ledger.list_accounts(scope), Ledger.balances(scope))

  def build(accounts, balances) do
    rows = Enum.map(accounts, &row(&1, balances))

    [
      group(:budget, "Budget", Enum.filter(rows, &(open?(&1) and budget?(&1)))),
      group(:tracking, "Tracking", Enum.filter(rows, &(open?(&1) and not budget?(&1)))),
      group(:closed, "Geschlossen", Enum.reject(rows, &open?/1))
    ]
    |> Enum.reject(&(&1.rows == []))
  end

  @doc "The groups without the closed accounts."
  def open(groups), do: Enum.reject(groups, &(&1.key == :closed))

  @doc "The open groups as the sidebar lists them: without the portfolios' accounts, which it lists under Depots."
  def sidebar(groups) do
    for group <- open(groups),
        rows = Enum.reject(group.rows, &(&1.account.fed_by == :portfolio)),
        rows != [],
        do: group(group.key, group.label, rows)
  end

  @doc "Every account's row, the closed ones included."
  def rows(groups), do: Enum.flat_map(groups, & &1.rows)

  defp row(account, balances) do
    %{balance: balance, cleared: cleared, unapproved: unapproved} =
      Map.merge(@no_transactions, Map.get(balances, account.id, %{}))

    %{account: account, balance: balance, cleared: cleared, unapproved: unapproved}
  end

  defp group(key, label, rows) do
    %{
      key: key,
      label: label,
      rows: rows,
      balance: rows |> Enum.map(& &1.balance) |> Enum.sum()
    }
  end

  defp open?(%{account: account}), do: not account.closed
  defp budget?(%{account: account}), do: Account.budget_account?(account)
end

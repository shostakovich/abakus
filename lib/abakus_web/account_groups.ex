defmodule AbakusWeb.AccountGroups do
  @moduledoc """
  Accounts as the sidebar and the registers group them: open budget accounts, open tracking accounts, then the
  closed ones, each account with its working and cleared balance and how many of its transactions wait for approval,
  each group with its working balance. Empty groups are left out, and so is the portfolios' cash
  (`Abakus.Depot.Portfolios.cash_account_portfolios/1`), whose money moves in the Depot.

  The sidebar lists the open groups as sections (`section/1`). Its `on_mount` handles the event `move_account` on
  every page with the sidebar: `%{"section" => section, "id" => id, "index" => index}` moves that section's account
  to `index` among the section's entries, before the one listed there now, so the accounts it leaves out keep their
  place; an id the section does not list changes nothing. It also reloads `account_groups` when another device
  synced (`{:synced, device}`). A LiveView that handles either itself too declares
  `on_mount {AbakusWeb.AccountGroups, {:pass_on, [:synced, :move_account]}}` (or one of them) and gets it after the
  groups were reloaded; it does not subscribe to the sync itself, which would deliver `{:synced, device}` twice.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, put_private: 3]

  alias Abakus.Depot.Portfolios
  alias Abakus.{Ledger, Sync}
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
    budget? = Areas.allowed?(socket.assigns.current_scope, :budget)
    if budget? and connected?(socket), do: Sync.subscribe(socket.assigns.current_scope)

    {:cont,
     socket
     |> reload()
     |> attach_hook(:move_account, :handle_event, &handle_event/3)
     |> attach_hook(:account_groups_synced, :handle_info, &handle_info/2)}
  end

  def on_mount({:pass_on, passed}, _params, _session, socket),
    do: {:cont, put_private(socket, :account_groups_pass_on, passed)}

  defp handle_event("move_account", params, socket) do
    move(socket.assigns, params)
    socket |> reload() |> pass_on(:move_account)
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_info({:synced, _device}, socket), do: socket |> reload() |> pass_on(:synced)
  defp handle_info(_message, socket), do: {:cont, socket}

  defp pass_on(socket, message) do
    if message in Map.get(socket.private, :account_groups_pass_on, []),
      do: {:cont, socket},
      else: {:halt, socket}
  end

  defp reload(socket) do
    scope = socket.assigns.current_scope
    assign(socket, :account_groups, if(Areas.allowed?(scope, :budget), do: load(scope), else: []))
  end

  defp move(%{current_scope: scope, account_groups: groups}, %{
         "section" => section,
         "id" => id,
         "index" => index
       })
       when is_integer(index) and index >= 0 do
    ids =
      for %{rows: rows} = group <- open(groups),
          section(group) == section,
          row <- rows,
          do: row.account.id

    if id in ids,
      do: Ledger.move_account(scope, id, ids |> List.delete(id) |> Enum.at(index)),
      else: {:error, :not_listed}
  end

  defp move(_assigns, _params), do: {:error, :malformed}

  @doc "The sidebar's section of an open group."
  def section(%{key: :budget}), do: "Budgetkonten"
  def section(%{key: :tracking}), do: "Trackingkonten"

  def load(%Scope{} = scope) do
    cash = Portfolios.cash_account_portfolios(scope)

    scope
    |> Ledger.list_accounts()
    |> Enum.reject(&Map.has_key?(cash, &1.id))
    |> build(Ledger.balances(scope))
  end

  def build(accounts, balances) do
    rows = Enum.map(accounts, &row(&1, balances))

    [
      group(:budget, "Budget", Enum.filter(rows, &(open?(&1) and budget?(&1)))),
      group(:tracking, "Tracking", Enum.filter(rows, &(open?(&1) and not budget?(&1)))),
      group(:closed, "Geschlossen", Enum.reject(rows, &open?/1))
    ]
    |> Enum.reject(&(&1.rows == []))
  end

  @doc "The groups without the closed accounts, as the sidebar lists them."
  def open(groups), do: Enum.reject(groups, &(&1.key == :closed))

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

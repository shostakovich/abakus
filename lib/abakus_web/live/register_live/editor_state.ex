defmodule AbakusWeb.RegisterLive.EditorState do
  @moduledoc """
  The state behind `AbakusWeb.RegisterLive.EditorFields`, in a live component's socket: the form's
  `AbakusWeb.TransactionForm` params, the payees and categories it offers, which categories are suggestions and
  which parts show a payee field of their own. Needs `current_scope`, `today` and `accounts` (by id, with their
  transfer payees).

  A choice in a combobox arrives as a change of `payee_pick` (with `payee_new` for a payee typed anew) or
  `category_pick`. A payee suggests its last category, and a suggestion goes again when the payee changes; a chosen
  category stays. A transfer between a budget and a tracking account suggests the category last used between the
  two. Income goes to Ready to Assign unless a category is chosen.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]

  alias Abakus.{Categories, Ledger, Names}
  alias AbakusWeb.{CategoryOptions, TransactionForm}

  @main "main"
  @picks ~w(payee_pick payee_new category_pick)

  @doc "Starts the state with the form's params."
  def load(socket, params) do
    %{current_scope: scope, today: today} = socket.assigns
    payees = Ledger.list_payees(scope)

    assign(socket,
      main: @main,
      params: params,
      suggested: MapSet.new(),
      payee_shown: MapSet.new(),
      payees: payees,
      payees_by_key: Map.new(payees, &{&1.lookup_key, &1}),
      ready_to_assign_id: Categories.ready_to_assign!(scope).id,
      categories: CategoryOptions.build(scope, today)
    )
  end

  @doc ~s|Takes a `change` event of the form (`%{"transaction" => …, "_target" => …}`).|
  def change(socket, %{"transaction" => changed} = event) do
    {picks, changed} = picks(changed)
    params = TransactionForm.change(socket.assigns.params, changed, socket.assigns.accounts)

    case pick_target(event["_target"]) do
      {side, field} -> socket |> assign(:params, params) |> pick(side, field, picks[side])
      nil -> after_change(socket, params, event["_target"])
    end
  end

  @doc """
  The params with a submitted form's fields. Submitting cancels a pending debounced change, so its amount arrives
  only here and still turns the category as a change would.
  """
  def submitted(socket, event) do
    %{accounts: accounts, params: before, ready_to_assign_id: rta} = socket.assigns
    {_picks, changed} = picks(event["transaction"] || %{})
    params = TransactionForm.change(before, changed, accounts)

    if TransactionForm.amount(params) == TransactionForm.amount(before),
      do: params,
      else: TransactionForm.follow_direction(params, rta, accounts)
  end

  @doc """
  Takes the events `EditorFields` sends to its component: "split", "toggle_sign" (of the whole transaction without
  a side, else of the side's), "show_sub_payee", "add_subtransaction" and "remove_subtransaction".
  """
  def handle_event("split", _params, socket), do: split(socket)

  def handle_event("toggle_sign", %{"side" => side}, socket) when side != @main,
    do: update(socket, :params, &TransactionForm.toggle_sign(&1, side))

  def handle_event("toggle_sign", params, socket),
    do: directed(socket, toggle(socket.assigns.params, params["side"]))

  def handle_event("show_sub_payee", %{"index" => index}, socket),
    do: update(socket, :payee_shown, &MapSet.put(&1, index))

  def handle_event("add_subtransaction", _params, socket),
    do: update(socket, :params, &TransactionForm.add_subtransaction/1)

  def handle_event("remove_subtransaction", %{"index" => index}, socket),
    do: update(socket, :params, &TransactionForm.remove_subtransaction(&1, index))

  defp split(socket), do: update(socket, :params, &TransactionForm.split/1)

  defp toggle(params, nil), do: TransactionForm.toggle_sign(params)
  defp toggle(params, @main), do: TransactionForm.toggle_sign(params, @main)

  @doc """
  Narrows the `accounts` assign to those the editor knows: a portfolio's cash is the Depot's, and with
  `hide_shared_expenses: true` the shared-expenses account is the Kasse's; each stays where `record`, the
  transaction or scheduled transaction edited (nil for a new one), uses it.
  """
  def assign_accounts(socket, record, opts \\ []) do
    %{accounts: accounts, depot_cash: depot_cash} = socket.assigns
    used = used_accounts(record)

    hidden? = fn account ->
      Map.has_key?(depot_cash, account.id) or
        (opts[:hide_shared_expenses] == true and account.shared_expenses)
    end

    assign(
      socket,
      :accounts,
      Map.reject(accounts, fn {id, account} -> hidden?.(account) and id not in used end)
    )
  end

  @doc "The ids of the accounts `record` and its parts use, its own and those they transfer to (payees preloaded)."
  def used_accounts(nil), do: MapSet.new()

  def used_accounts(record) do
    [record | record.subtransactions]
    |> Enum.map(&(&1.payee && &1.payee.transfer_account_id))
    |> then(&[record.account_id | &1])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp picks(changed) do
    subs = changed["subtransactions"] || %{}

    picks =
      Map.new(subs, fn {index, sub} -> {index, Map.take(sub, @picks)} end)
      |> Map.put(@main, Map.take(changed, @picks))

    subs = Map.new(subs, fn {index, sub} -> {index, Map.drop(sub, @picks)} end)

    changed =
      changed
      |> Map.drop(@picks)
      |> then(&if(&1["subtransactions"], do: Map.put(&1, "subtransactions", subs), else: &1))

    {picks, changed}
  end

  defp pick_target(["transaction", field]) when field in ["payee_pick", "category_pick"],
    do: {@main, field}

  defp pick_target(["transaction", "subtransactions", index, field])
       when field in ["payee_pick", "category_pick"],
       do: {index, field}

  defp pick_target(_target), do: nil

  defp pick(socket, side, "payee_pick", picked) do
    %{params: params, accounts: accounts} = socket.assigns

    case picked || %{} do
      %{"payee_pick" => "a:" <> id} ->
        params = TransactionForm.pick_payee(params, side, {:transfer, id})

        suggest(
          socket,
          params,
          side,
          socket.assigns.current_scope
          |> transfer_category(params, side, accounts)
          |> suggest_offered(socket)
        )

      %{"payee_pick" => "p:" <> name} ->
        payee(socket, params, side, name)

      picked ->
        payee(socket, params, side, picked["payee_new"] || "")
    end
  end

  defp pick(socket, side, "category_pick", %{"category_pick" => "split"}) when side == @main,
    do: split(socket)

  defp pick(socket, side, "category_pick", %{"category_pick" => id}) do
    cond do
      id == "" ->
        put_category(socket, side, "")

      TransactionForm.to_id(id) in CategoryOptions.ids(socket.assigns.categories) ->
        put_category(socket, side, id)

      true ->
        socket
    end
  end

  defp pick(socket, _side, _field, _picked), do: socket

  defp payee(socket, params, side, name) do
    name = String.trim(name)
    params = TransactionForm.pick_payee(params, side, {:payee, name})
    suggest(socket, params, side, payee_category(socket, name))
  end

  defp put_category(socket, side, id) do
    params = TransactionForm.put_side(socket.assigns.params, side, %{"category_id" => id})
    assign(socket, params: params, suggested: MapSet.delete(socket.assigns.suggested, side))
  end

  defp after_change(socket, params, ["transaction", "amount"]), do: directed(socket, params)
  defp after_change(socket, params, _target), do: assign(socket, :params, params)

  defp directed(socket, params) do
    %{ready_to_assign_id: rta, accounts: accounts} = socket.assigns
    params = TransactionForm.follow_direction(params, rta, accounts)
    suggested = socket.assigns.suggested

    suggested =
      if params["category_id"] == "", do: MapSet.delete(suggested, @main), else: suggested

    assign(socket, params: params, suggested: suggested)
  end

  defp suggest(socket, params, side, category_id) do
    suggested? = MapSet.member?(socket.assigns.suggested, side)
    {params, suggested} = TransactionForm.suggest(params, side, category_id, suggested?)
    set = if suggested, do: &MapSet.put/2, else: &MapSet.delete/2
    assign(socket, params: params, suggested: set.(socket.assigns.suggested, side))
  end

  defp payee_category(socket, name) do
    case Map.get(socket.assigns.payees_by_key, Names.lookup_key(name)) do
      %{last_category_id: id} -> offered(socket, id)
      nil -> nil
    end
  end

  defp transfer_category(current_scope, params, side, accounts) do
    case TransactionForm.crossing(params, side, accounts) do
      {budget, tracking} ->
        Ledger.last_transfer_category_id(current_scope, budget.id, tracking.transfer_payee.id)

      nil ->
        nil
    end
  end

  defp suggest_offered(nil, _socket), do: nil
  defp suggest_offered(id, socket), do: offered(socket, id)

  defp offered(socket, id), do: if(id in CategoryOptions.ids(socket.assigns.categories), do: id)
end

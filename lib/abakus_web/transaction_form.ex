defmodule AbakusWeb.TransactionForm do
  @moduledoc """
  A transaction as the register edits it, as params with string keys, and the attrs for the Ledger built from
  them.

  As in YNAB an amount is typed as an outflow or an inflow (`outflow`, `inflow`): it is inflow − outflow, so a
  minus counts against its column. Phones type one amount, which `sign` ("-" or "+") makes the outflow or the
  inflow.

  The transaction and each subtransaction of a split (with `split` "true", `subtransactions` by index) are sides:
  each has a `payee`, a `transfer_account_id` and a `category_id`; a subtransaction also has a memo, an amount and
  its `id` when it exists already. A transfer is picked as a payee, "↔ Account" (`transfer_label/1`): then
  `transfer_account_id` names the other account and `payee` is empty.

  A category goes on the budget side of a transfer between a budget and a tracking account, which is
  `counterpart_category_id` when that side is the counterpart; transfers between budget accounts and tracking
  accounts have none. Accounts are `%{id => %Account{}}` with their transfer payees.
  """

  alias Abakus.Ledger.{Account, Payee, Transaction}
  alias AbakusWeb.Format

  @main "main"

  @doc "A blank form for a new transaction in the account on the date."
  def new(account_id, %Date{} = date) do
    %{
      "account_id" => to_param(account_id),
      "date" => Date.to_iso8601(date),
      "sign" => "-",
      "split" => "false",
      "subtransactions" => %{},
      "memo" => ""
    }
    |> Map.merge(blank_side())
  end

  @doc "The form for a transaction from `Abakus.Ledger.get_transaction!/1`."
  def from_transaction(%Transaction{} = transaction) do
    split? = transaction.subtransactions != []

    subtransactions =
      transaction.subtransactions
      |> Enum.with_index()
      |> Map.new(fn {subtransaction, index} ->
        {Integer.to_string(index),
         subtransaction
         |> side_params()
         |> Map.merge(%{"id" => to_param(subtransaction.id), "memo" => subtransaction.memo || ""})}
      end)

    transaction
    |> side_params()
    |> Map.merge(%{
      "account_id" => to_param(transaction.account_id),
      "date" => Date.to_iso8601(transaction.date),
      "sign" => if(transaction.amount > 0, do: "+", else: "-"),
      "split" => to_string(split?),
      "subtransactions" => subtransactions,
      "memo" => transaction.memo || ""
    })
  end

  defp side_params(side) do
    transfer = transfer_account_id(side.payee)

    %{
      "payee" => if(transfer, do: "", else: payee_name(side.payee)),
      "transfer_account_id" => to_param(transfer),
      "category_id" => to_param(category_id(side)),
      "outflow" => if(side.amount < 0, do: Format.amount(-side.amount), else: ""),
      "inflow" => if(side.amount > 0, do: Format.amount(side.amount), else: "")
    }
  end

  # A transfer's category is on its budget side, which may be the counterpart.
  defp category_id(%{category_id: nil, transfer_transaction: %Transaction{category_id: id}}),
    do: id

  defp category_id(side), do: side.category_id

  defp transfer_account_id(%Payee{transfer_account_id: id}), do: id
  defp transfer_account_id(_payee), do: nil

  defp payee_name(%Payee{name: name}), do: name
  defp payee_name(_payee), do: ""

  @doc ~S|How a transfer to or from the account shows as a payee: "↔ Sparkonto".|
  def transfer_label(%Account{name: name}), do: "↔ " <> name

  @doc """
  Takes typed params into the form. What is picked (categories, transfers) and which subtransactions there are is
  the form's own, so the browser's copy of it, which may lag behind, does not count. A payee typed over a
  transfer's label is a payee again, not the transfer.
  """
  def change(params, changed, accounts) do
    subtransactions =
      Map.new(params["subtransactions"] || %{}, fn {index, sub} ->
        {index,
         sub
         |> Map.merge(typed(get_in(changed, ["subtransactions", index])))
         |> follow_payee(accounts)}
      end)

    params
    |> Map.merge(changed |> typed() |> Map.delete("subtransactions"))
    |> follow_payee(accounts)
    |> Map.put("subtransactions", subtransactions)
  end

  @owned ~w(id category_id transfer_account_id split sign)

  defp typed(changed) when is_map(changed), do: Map.drop(changed, @owned)
  defp typed(_none), do: %{}

  # The payee typed while a transfer is picked: its label keeps the transfer, anything else replaces it.
  defp follow_payee(%{"transfer_account_id" => id, "payee" => payee} = side, accounts)
       when id not in [nil, ""] and payee not in [nil, ""] do
    case account(id, accounts) do
      %Account{} = account ->
        if payee == transfer_label(account),
          do: %{side | "payee" => ""},
          else: %{side | "transfer_account_id" => ""}

      nil ->
        %{side | "transfer_account_id" => ""}
    end
  end

  defp follow_payee(side, _accounts), do: side

  defp map_sides(params, fun) do
    params
    |> fun.()
    |> Map.update("subtransactions", %{}, &Map.new(&1, fn {index, sub} -> {index, fun.(sub)} end))
  end

  @doc "A side's params: \"main\" is the transaction, an index a subtransaction."
  def side(params, @main), do: params
  def side(params, index), do: get_in(params, ["subtransactions", index]) || %{}

  @doc "Puts `changes` into a side; a subtransaction that is gone stays gone."
  def put_side(params, @main, changes), do: Map.merge(params, changes)

  def put_side(params, index, changes) do
    if Map.has_key?(params["subtransactions"] || %{}, index),
      do: update_in(params, ["subtransactions", index], &Map.merge(&1, changes)),
      else: params
  end

  @doc "Whether the side is a transfer."
  def transfer?(side), do: side["transfer_account_id"] not in [nil, ""]

  @doc "Picks a payee for the side: `{:transfer, account_id}` or `{:payee, name}`."
  def pick_payee(params, side, {:transfer, account_id}),
    do: put_side(params, side, %{"payee" => "", "transfer_account_id" => to_param(account_id)})

  def pick_payee(params, side, {:payee, name}),
    do: put_side(params, side, %{"payee" => name, "transfer_account_id" => ""})

  @doc """
  After the payee changed: a suggested category (the payee's last) replaces the side's category; without one a
  suggested category is cleared and a chosen one kept. Returns the params and whether the category is a suggestion.
  """
  def suggest(params, side, category_id, suggested?)

  def suggest(params, side, category_id, _suggested?) when not is_nil(category_id),
    do: {put_side(params, side, %{"category_id" => to_param(category_id)}), true}

  def suggest(params, side, nil, true = _suggested?),
    do: {put_side(params, side, %{"category_id" => ""}), false}

  def suggest(params, _side, nil, false = _suggested?), do: {params, false}

  @doc "YNAB keeps one of outflow and inflow: typing into one (`column`) clears the other."
  def keep_column(params, side, column) when column in ["outflow", "inflow"] do
    other = if column == "outflow", do: "inflow", else: "outflow"

    if String.trim(side(params, side)[column] || "") == "",
      do: params,
      else: put_side(params, side, %{other => ""})
  end

  @doc """
  After the amount changed direction: income goes to Ready to Assign unless a category is chosen, and an outflow
  does not keep Ready to Assign.
  """
  def follow_direction(params, ready_to_assign_id) do
    rta = to_param(ready_to_assign_id)

    case {amount(params), params} do
      {_amount, %{"split" => "true"}} -> params
      {{:ok, amount}, %{"category_id" => ""}} when amount > 0 -> %{params | "category_id" => rta}
      {{:ok, amount}, %{"category_id" => ^rta}} when amount < 0 -> %{params | "category_id" => ""}
      _same -> params
    end
  end

  @doc "Flips the sign of the phone's amount: outflows become inflows and back, the parts' too."
  def toggle_sign(params) do
    swap = fn side -> %{side | "outflow" => side["inflow"], "inflow" => side["outflow"]} end
    sign = if params["sign"] == "+", do: "-", else: "+"

    params
    |> map_sides(&Map.merge(%{"outflow" => "", "inflow" => ""}, &1))
    |> map_sides(swap)
    |> Map.put("sign", sign)
  end

  @doc """
  The phone's amount of a side in the transaction's direction (`sign`), as typed while only one column is filled.
  """
  def directed(side, sign) do
    {column, other} = if sign == "+", do: {"inflow", "outflow"}, else: {"outflow", "inflow"}

    cond do
      blank?(side[other]) -> side[column] || ""
      match?({:ok, _}, amount(side)) -> Format.amount(direction(sign) * elem(amount(side), 1))
      true -> side[other]
    end
  end

  defp direction("+"), do: 1
  defp direction(_sign), do: -1

  @doc "Splits the transaction into two blank subtransactions; its category goes, as a split has none."
  def split(params) do
    subtransactions =
      if subtransactions(params) == [],
        do: %{"0" => blank_subtransaction(), "1" => blank_subtransaction()},
        else: params["subtransactions"]

    %{
      params
      | "split" => "true",
        "subtransactions" => subtransactions,
        "category_id" => "",
        "transfer_account_id" => ""
    }
  end

  @doc "The subtransactions in order as `{index, subtransaction}`."
  def subtransactions(params) do
    params
    |> Map.get("subtransactions", %{})
    |> Enum.sort_by(fn {index, _subtransaction} -> String.to_integer(index) end)
  end

  def add_subtransaction(params) do
    next =
      params
      |> subtransactions()
      |> Enum.map(&String.to_integer(elem(&1, 0)))
      |> Enum.max(fn -> -1 end)

    put_in(params, ["subtransactions", Integer.to_string(next + 1)], blank_subtransaction())
  end

  @doc """
  Removes a subtransaction. A split keeps at least two: removing one of the last two ends the split, and the
  transaction takes the other's category.
  """
  def remove_subtransaction(params, index) do
    case Enum.reject(subtransactions(params), &(elem(&1, 0) == index)) do
      [{_index, last}] ->
        category_id = if transfer?(last), do: "", else: last["category_id"] || ""
        %{params | "split" => "false", "subtransactions" => %{}, "category_id" => category_id}

      _more ->
        Map.update!(params, "subtransactions", &Map.delete(&1, index))
    end
  end

  @doc "What is left to split: the amount less the subtransactions', signed; nil while unreadable."
  def remainder(params) do
    amounts = Enum.map(subtransactions(params), fn {_index, sub} -> amount(sub) end)

    with {:ok, amount} <- amount(params),
         true <- Enum.all?(amounts, &match?({:ok, _}, &1)) do
      amount - Enum.sum(Enum.map(amounts, &elem(&1, 1)))
    else
      _unreadable -> nil
    end
  end

  @doc "A side's amount: inflow − outflow, blanks as zero."
  def amount(side) do
    with {:ok, outflow} <- Format.parse_amount(side["outflow"] || ""),
         {:ok, inflow} <- Format.parse_amount(side["inflow"] || "") do
      {:ok, inflow - outflow}
    end
  end

  @doc """
  Whether the side takes a category: a split does not, a transfer only between a budget and a tracking account,
  anything else when the transaction's account is a budget account.
  """
  def category?(params, side, accounts) do
    account = account(params["account_id"], accounts)

    case {side, side(params, side)} do
      {@main, %{"split" => "true"}} ->
        false

      {_side, %{"transfer_account_id" => id} = values} when id not in [nil, ""] ->
        transfer?(values) and crossing?(account, account(id, accounts))

      _plain ->
        is_nil(account) or Account.takes_category?(account)
    end
  end

  # A transfer takes a category on its budget side, the transaction's or the counterpart's.
  defp crossing?(%Account{} = account, %Account{} = other),
    do: Account.takes_category?(account, other) or Account.takes_category?(other, account)

  defp crossing?(_account, _other), do: false

  @doc "For a transfer between a budget and a tracking account: `{budget_account, tracking_account}`."
  def crossing(params, side, accounts) do
    with %Account{} = account <- account(params["account_id"], accounts),
         %Account{} = other <- account(side(params, side)["transfer_account_id"], accounts),
         true <- crossing?(account, other) do
      if Account.budget_account?(account), do: {account, other}, else: {other, account}
    else
      _no -> nil
    end
  end

  @doc """
  The Ledger attrs for the form, approved, as a person entered them; `original` is the transaction edited, if any.
  Returns `{:error, message}` for what the Ledger cannot check: amounts, date and accounts.
  """
  def to_attrs(params, accounts, original \\ nil) do
    with {:ok, account} <- fetch_account(params["account_id"], accounts, "Konto"),
         {:ok, date} <- parse_date(params["date"]),
         {:ok, amount} <- parse_amount(params, ""),
         {:ok, details} <- details(params, account, accounts, original) do
      {:ok,
       Map.merge(
         %{
           account_id: account.id,
           date: date,
           amount: amount,
           memo: blank_to_nil(params["memo"]),
           approved: true
         },
         details
       )}
    end
  end

  defp details(%{"split" => "true"} = params, account, accounts, original) do
    with {:ok, subtransactions} <- to_subtransactions(params, account, accounts, original),
         :ok <- two_or_more(subtransactions) do
      {:ok,
       %{payee_name: params["payee"] || "", category_id: nil, subtransactions: subtransactions}}
    end
  end

  defp details(params, account, accounts, _original) do
    with {:ok, side} <- side_attrs(params, nil, account, accounts) do
      {:ok, Map.put(side, :subtransactions, [])}
    end
  end

  defp two_or_more([_, _ | _]), do: :ok

  defp two_or_more(_subtransactions),
    do: {:error, "Eine Aufteilung braucht mindestens zwei Teile"}

  # A transfer's payee is the other account's transfer payee; any other payee goes by name. The transaction drops
  # its category in a tracking account; a subtransaction (`prefix` names it) keeps it for the Ledger to refuse.
  defp side_attrs(side, prefix, account, accounts) do
    cond do
      transfer?(side) ->
        with {:ok, other} <-
               fetch_account(side["transfer_account_id"], accounts, "#{prefix}Konto"),
             {:ok, category} <-
               transfer_category(account, other, side["category_id"], prefix || "") do
          {:ok, Map.put(category, :payee_id, other.transfer_payee.id)}
        end

      prefix || Account.takes_category?(account) ->
        {:ok, %{payee_name: side["payee"] || "", category_id: to_id(side["category_id"])}}

      true ->
        {:ok, %{payee_name: side["payee"] || "", category_id: nil}}
    end
  end

  # The counterpart keeps its category when none is given, so a cleared one is refused here.
  defp transfer_category(account, other, category_id, prefix) do
    cond do
      Account.takes_category?(account, other) ->
        {:ok, %{category_id: to_id(category_id)}}

      not Account.takes_category?(other, account) ->
        {:ok, %{category_id: nil}}

      id = to_id(category_id) ->
        {:ok, %{category_id: nil, counterpart_category_id: id}}

      true ->
        {:error,
         "#{prefix}Kategorie muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"}
    end
  end

  defp to_subtransactions(params, account, accounts, original) do
    kept = kept_ids(original)

    params
    |> subtransactions()
    |> Enum.map(&elem(&1, 1))
    |> Enum.reject(&blank_subtransaction?/1)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {sub, number}, {:ok, done} ->
      case to_subtransaction(sub, "Teil #{number}: ", account, accounts, kept) do
        {:ok, sub} -> {:cont, {:ok, [sub | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  defp kept_ids(%Transaction{subtransactions: subtransactions}),
    do: MapSet.new(subtransactions, &to_param(&1.id))

  defp kept_ids(nil), do: MapSet.new()

  defp blank_subtransaction?(sub),
    do: Enum.all?(~w(payee transfer_account_id category_id memo outflow inflow), &blank?(sub[&1]))

  defp to_subtransaction(sub, prefix, account, accounts, kept) do
    with {:ok, amount} <- parse_amount(sub, prefix),
         {:ok, side} <- side_attrs(sub, prefix, account, accounts) do
      side = Map.merge(side, %{amount: amount, memo: blank_to_nil(sub["memo"])})

      {:ok,
       if(sub["id"] in kept, do: Map.put(side, :id, String.to_integer(sub["id"])), else: side)}
    end
  end

  defp fetch_account(id, accounts, label) do
    case account(id, accounts) do
      nil -> {:error, "#{label} muss ausgewählt werden"}
      account -> {:ok, account}
    end
  end

  defp account(id, accounts), do: to_id(id) && Map.get(accounts, to_id(id))

  defp parse_date(text) do
    case Date.from_iso8601(text || "") do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "Datum ist ungültig"}
    end
  end

  defp parse_amount(side, prefix) do
    case amount(side) do
      {:ok, cents} -> {:ok, cents}
      :error -> {:error, "#{prefix}Betrag ist ungültig"}
    end
  end

  defp blank_side,
    do: %{
      "payee" => "",
      "transfer_account_id" => "",
      "category_id" => "",
      "outflow" => "",
      "inflow" => ""
    }

  defp blank_subtransaction, do: Map.merge(blank_side(), %{"id" => "", "memo" => ""})

  defp blank?(text), do: String.trim(text || "") == ""

  defp blank_to_nil(text) do
    case String.trim(text || "") do
      "" -> nil
      text -> text
    end
  end

  defp to_param(nil), do: ""
  defp to_param(id), do: to_string(id)

  @doc "The id in a param, nil when there is none."
  def to_id(id) when is_integer(id), do: id

  def to_id(text) when is_binary(text) do
    case Integer.parse(text) do
      {id, ""} -> id
      _other -> nil
    end
  end

  def to_id(_none), do: nil
end

defmodule AbakusWeb.TransactionForm do
  @moduledoc """
  A transaction as the transaction form edits it, as form params with string keys, and the attrs for the Ledger
  built from them.

  The amount is typed without its sign; `sign` ("-" outflow, "+" inflow) gives it. `kind` is "outflow", "inflow"
  or "transfer": the first two follow the sign, a transfer keeps its own (to `other_account_id` or from it). With
  `split` the `subtransactions` (by index) add up to the amount; each picks a category ("c:ID") or an account
  ("a:ID") in `target`, and its amount counts in the transaction's direction, a negative one against it. Payees
  and memos of existing subtransactions are not in the form, so the Ledger keeps them.

  A category goes on the budget side of a transfer between a budget and a tracking account, which is
  `counterpart_category_id` when that side is the counterpart; transfers between budget accounts and tracking
  accounts have none. Accounts are `%{id => %Account{}}` with their transfer payees.
  """

  alias Abakus.Ledger.{Account, Payee, Transaction}
  alias AbakusWeb.Format

  @doc "A blank form for a new outflow in the account on the date, with two subtransactions ready for a split."
  def new(account_id, %Date{} = date) do
    %{
      "account_id" => to_param(account_id),
      "date" => Date.to_iso8601(date),
      "amount" => "",
      "sign" => "-",
      "kind" => "outflow",
      "payee" => "",
      "category_id" => "",
      "other_account_id" => "",
      "split" => "false",
      "subtransactions" => blank_subtransactions(),
      "memo" => ""
    }
  end

  @doc "The form for a transaction from `Abakus.Ledger.get_transaction!/1`."
  def from_transaction(%Transaction{} = transaction) do
    sign = if transaction.amount < 0, do: "-", else: "+"
    other = transfer_account_id(transaction.payee)
    split? = transaction.subtransactions != []

    %{
      "account_id" => to_param(transaction.account_id),
      "date" => Date.to_iso8601(transaction.date),
      "amount" => Format.amount(abs(transaction.amount)),
      "sign" => sign,
      "kind" => if(other && not split?, do: "transfer", else: kind(sign)),
      "payee" => if(other, do: "", else: payee_name(transaction.payee)),
      "category_id" => to_param(category_id(transaction)),
      "other_account_id" => to_param(other),
      "split" => to_string(split?),
      "subtransactions" =>
        if(split?, do: subtransactions_of(transaction, sign), else: blank_subtransactions()),
      "memo" => transaction.memo || ""
    }
  end

  defp subtransactions_of(transaction, sign) do
    transaction.subtransactions
    |> Enum.with_index()
    |> Map.new(fn {subtransaction, index} ->
      {Integer.to_string(index),
       %{
         "id" => to_param(subtransaction.id),
         "target" => target(subtransaction),
         "amount" => Format.amount(signed(subtransaction.amount, sign)),
         "category_id" => to_param(category_id(subtransaction))
       }}
    end)
  end

  defp target(side) do
    case {transfer_account_id(side.payee), side.category_id} do
      {nil, nil} -> ""
      {nil, category_id} -> "c:#{category_id}"
      {account_id, _category_id} -> "a:#{account_id}"
    end
  end

  # A transfer's category is on its budget side, which may be the counterpart.
  defp category_id(%{category_id: nil, transfer_transaction: %Transaction{category_id: id}}),
    do: id

  defp category_id(side), do: side.category_id

  defp transfer_account_id(%Payee{transfer_account_id: id}), do: id
  defp transfer_account_id(_payee), do: nil

  defp payee_name(%Payee{name: name}), do: name
  defp payee_name(_payee), do: ""

  @doc "Takes changed params into the form: subtransactions only when given, an outflow or inflow follows its kind."
  def change(params, changed) do
    params |> Map.merge(changed) |> follow_kind()
  end

  defp follow_kind(%{"kind" => "outflow"} = params), do: Map.put(params, "sign", "-")
  defp follow_kind(%{"kind" => "inflow"} = params), do: Map.put(params, "sign", "+")
  defp follow_kind(%{"kind" => "transfer"} = params), do: params
  defp follow_kind(params), do: Map.put(params, "kind", kind(params["sign"]))

  defp kind("+"), do: "inflow"
  defp kind(_sign), do: "outflow"

  @doc "Flips the sign; an outflow becomes an inflow and back, a transfer changes its direction."
  def toggle_sign(params) do
    sign = if params["sign"] == "-", do: "+", else: "-"
    kind = if params["kind"] == "transfer", do: "transfer", else: kind(sign)
    %{params | "sign" => sign, "kind" => kind}
  end

  @doc """
  After the kind changed: income goes to Ready to Assign unless a category is chosen, and an outflow does not keep
  Ready to Assign.
  """
  def kind_changed(params, ready_to_assign_id) do
    rta = to_param(ready_to_assign_id)

    case params do
      %{"kind" => "inflow", "category_id" => ""} -> %{params | "category_id" => rta}
      %{"kind" => "outflow", "category_id" => ^rta} -> %{params | "category_id" => ""}
      params -> params
    end
  end

  @doc """
  After the payee changed: a payee with a last category suggests it; otherwise a suggested category is cleared and
  a chosen one kept. Returns the params and whether the category is a suggestion.
  """
  def suggest(params, %Payee{last_category_id: id}, _suggested?) when not is_nil(id),
    do: {%{params | "category_id" => to_param(id)}, true}

  def suggest(params, _payee, true = _suggested?), do: {%{params | "category_id" => ""}, false}
  def suggest(params, _payee, false = _suggested?), do: {params, false}

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

  @doc "Removes a subtransaction; a split keeps at least two."
  def remove_subtransaction(params, index) do
    if length(subtransactions(params)) > 2,
      do: Map.update!(params, "subtransactions", &Map.delete(&1, index)),
      else: params
  end

  @doc """
  What is left to split: the amount less the subtransactions, in the transaction's direction; nil while unreadable.
  """
  def remainder(params) do
    amounts =
      Enum.map(subtransactions(params), fn {_index, subtransaction} ->
        Format.parse_amount(subtransaction["amount"])
      end)

    with {:ok, amount} <- Format.parse_amount(params["amount"]),
         true <- Enum.all?(amounts, &match?({:ok, _}, &1)) do
      abs(amount) - Enum.sum(Enum.map(amounts, &elem(&1, 1)))
    else
      _unreadable -> nil
    end
  end

  @doc "Whether the transaction itself takes a category."
  def category?(params, accounts) do
    account = account(params["account_id"], accounts)

    case params do
      %{"kind" => "transfer"} -> crossing?(account, account(params["other_account_id"], accounts))
      %{"split" => "true"} -> false
      _params -> is_nil(account) or Account.takes_category?(account)
    end
  end

  @doc "Whether a subtransaction takes a category of its own: a transfer between a budget and a tracking account."
  def subtransaction_category?(subtransaction, params, accounts) do
    case subtransaction["target"] do
      "a:" <> id -> crossing?(account(params["account_id"], accounts), account(id, accounts))
      _target -> false
    end
  end

  # A transfer takes a category on its budget side, the transaction's or the counterpart's.
  defp crossing?(%Account{} = account, %Account{} = other),
    do: Account.takes_category?(account, other) or Account.takes_category?(other, account)

  defp crossing?(_account, _other), do: false

  @doc """
  The Ledger attrs for the form, approved, as a person entered them; `original` is the transaction edited, if any.
  Returns `{:error, message}` for what the Ledger cannot check: amounts, date and accounts.
  """
  def to_attrs(params, accounts, original \\ nil) do
    with {:ok, account} <- fetch_account(params["account_id"], accounts, "Konto"),
         {:ok, date} <- parse_date(params["date"]),
         {:ok, amount} <- parse_amount(params["amount"], "Betrag"),
         {:ok, details} <- details(params, account, accounts, original) do
      {:ok,
       Map.merge(
         %{
           account_id: account.id,
           date: date,
           amount: signed(abs(amount), params["sign"]),
           memo: blank_to_nil(params["memo"]),
           approved: true
         },
         details
       )}
    end
  end

  defp details(%{"kind" => "transfer"} = params, account, accounts, _original) do
    with {:ok, other} <- fetch_account(params["other_account_id"], accounts, "Gegenkonto"),
         {:ok, category} <- transfer_category(account, other, params["category_id"], "") do
      {:ok, Map.merge(%{payee_id: other.transfer_payee.id, subtransactions: []}, category)}
    end
  end

  defp details(%{"split" => "true"} = params, account, accounts, original) do
    with {:ok, subtransactions} <- to_subtransactions(params, account, accounts, original),
         :ok <- two_or_more(subtransactions) do
      {:ok,
       %{payee_name: params["payee"] || "", category_id: nil, subtransactions: subtransactions}}
    end
  end

  defp details(params, account, _accounts, _original) do
    category_id = if Account.takes_category?(account), do: to_id(params["category_id"])
    {:ok, %{payee_name: params["payee"] || "", category_id: category_id, subtransactions: []}}
  end

  defp two_or_more([_, _ | _]), do: :ok

  defp two_or_more(_subtransactions),
    do: {:error, "Eine Aufteilung braucht mindestens zwei Teile"}

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
    kept = kept_subtransactions(original)

    params
    |> subtransactions()
    |> Enum.map(&elem(&1, 1))
    |> Enum.reject(&blank_subtransaction?/1)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {subtransaction, number}, {:ok, done} ->
      case to_subtransaction(subtransaction, number, params["sign"], account, accounts, kept) do
        {:ok, subtransaction} -> {:cont, {:ok, [subtransaction | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  # The original's subtransactions by id, with whether each is a transfer.
  defp kept_subtransactions(%Transaction{subtransactions: subtransactions}),
    do: Map.new(subtransactions, &{to_param(&1.id), transfer_account_id(&1.payee) != nil})

  defp kept_subtransactions(nil), do: %{}

  defp blank_subtransaction?(subtransaction),
    do:
      subtransaction["target"] in [nil, ""] and String.trim(subtransaction["amount"] || "") == ""

  defp to_subtransaction(subtransaction, number, sign, account, accounts, kept) do
    with {:ok, amount} <- parse_amount(subtransaction["amount"], "Teil #{number}: Betrag"),
         {:ok, side} <-
           subtransaction_side(subtransaction, "Teil #{number}: ", account, accounts, kept) do
      {:ok,
       side |> Map.put(:amount, signed(amount, sign)) |> put_kept_id(subtransaction["id"], kept)}
    end
  end

  defp subtransaction_side(
         %{"target" => "a:" <> id} = subtransaction,
         prefix,
         account,
         accounts,
         _kept
       ) do
    with {:ok, other} <- fetch_account(id, accounts, "#{prefix}Konto"),
         {:ok, category} <-
           transfer_category(account, other, subtransaction["category_id"], prefix) do
      {:ok, Map.put(category, :payee_id, other.transfer_payee.id)}
    end
  end

  # A subtransaction that was a transfer loses its transfer payee; other payees stay as they are.
  defp subtransaction_side(subtransaction, _prefix, _account, _accounts, kept) do
    category_id =
      case subtransaction["target"] do
        "c:" <> id -> to_id(id)
        _none -> nil
      end

    side = %{category_id: category_id}
    {:ok, if(Map.get(kept, subtransaction["id"]), do: Map.put(side, :payee_id, nil), else: side)}
  end

  defp put_kept_id(side, id, kept) do
    case Map.fetch(kept, id) do
      {:ok, _transfer?} -> Map.put(side, :id, String.to_integer(id))
      :error -> side
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

  defp parse_amount(text, label) do
    case Format.parse_amount(text || "") do
      {:ok, cents} -> {:ok, cents}
      :error -> {:error, "#{label} ist ungültig"}
    end
  end

  defp signed(amount, "+"), do: amount
  defp signed(amount, _outflow), do: -amount

  defp blank_subtransactions, do: %{"0" => blank_subtransaction(), "1" => blank_subtransaction()}

  defp blank_subtransaction,
    do: %{"id" => "", "target" => "", "amount" => "", "category_id" => ""}

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

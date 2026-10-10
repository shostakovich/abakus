defmodule AbakusWeb.Api.TransactionParams do
  @moduledoc """
  Reads the transactions of a YNAB save request (`{"transactions": […]}`) into Ledger attrs. The API writes exactly
  the fields the shared-expenses app sends; any other field is refused rather than dropped, so a client never takes
  a split or a flag for stored. Amounts come in milliunits and must be whole cents, ids must fit a row. Everything
  else the Ledger checks. Errors name the transaction by its position, in German.
  """

  alias Abakus.Schema

  @writable ~w(account_id date amount payee_name memo category_id cleared approved)

  @doc "The attrs of each transaction to create, in order."
  def for_create(params), do: read(params, &attrs/1)

  @doc "`{id, attrs}` of each transaction to change, in order; the id as the client sent it."
  def for_update(params), do: read(params, &change/1)

  defp read(%{"transactions" => [_ | _] = transactions}, read_one) do
    transactions
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {transaction, number}, {:ok, done} ->
      case read_one.(transaction) do
        {:ok, read} -> {:cont, {:ok, [read | done]}}
        {:error, message} -> {:halt, {:error, "Buchung #{number}: #{message}"}}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  defp read(_params, _read_one),
    do: {:error, "transactions muss eine Liste mit mindestens einer Buchung sein"}

  defp change(%{"id" => id} = transaction) do
    with {:ok, attrs} <- attrs(Map.delete(transaction, "id")), do: {:ok, {id, attrs}}
  end

  defp change(transaction) when is_map(transaction), do: {:error, "id fehlt"}
  defp change(_transaction), do: not_an_object()

  defp attrs(transaction) when is_map(transaction) do
    with :ok <- only_writable(transaction),
         :ok <- validate_ids(transaction),
         :ok <- validate_payee_name(transaction) do
      to_cents(transaction)
    end
  end

  defp attrs(_transaction), do: not_an_object()

  defp not_an_object, do: {:error, "ist kein Objekt"}

  defp only_writable(transaction) do
    case transaction |> Map.keys() |> Enum.reject(&(&1 in @writable)) |> Enum.sort() do
      [] -> :ok
      fields -> {:error, "#{Enum.join(fields, ", ")} schreibt die API nicht"}
    end
  end

  # The Ledger checks that they exist; an id no row can have would fail its query.
  defp validate_ids(transaction) do
    case Enum.find(~w(account_id category_id), &invalid_id?(Map.get(transaction, &1))) do
      nil -> :ok
      field -> {:error, "#{field} ist keine gültige Id"}
    end
  end

  defp invalid_id?(nil), do: false
  defp invalid_id?(id), do: Schema.cast_id(id) == :error

  defp validate_payee_name(%{"payee_name" => name}) when not is_binary(name) and not is_nil(name),
    do: {:error, "payee_name muss ein Text sein"}

  defp validate_payee_name(_transaction), do: :ok

  defp to_cents(%{"amount" => amount} = transaction)
       when is_integer(amount) and rem(amount, 10) == 0,
       do: {:ok, %{transaction | "amount" => div(amount, 10)}}

  defp to_cents(%{"amount" => amount}) when is_integer(amount),
    do: {:error, "amount #{amount} ist kein ganzer Cent-Betrag (Milliunits durch 10 teilbar)"}

  defp to_cents(%{"amount" => _amount}),
    do: {:error, "amount muss eine ganze Zahl in Milliunits sein"}

  defp to_cents(transaction), do: {:ok, transaction}
end

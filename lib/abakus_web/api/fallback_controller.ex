defmodule AbakusWeb.Api.FallbackController do
  @moduledoc "Turns what the API's actions refuse into YNAB's errors."

  alias Abakus.Ledger
  alias AbakusWeb.Api
  alias AbakusWeb.CoreComponents

  @behaviour Plug

  @impl true
  def init(result), do: result

  @impl true
  def call(conn, {:error, :not_found}), do: Api.send_not_found(conn)
  def call(conn, {:error, detail}) when is_binary(detail), do: Api.send_error(conn, 400, detail)

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    status = if Ledger.refused_as_reconciled?(changeset), do: 409, else: 400
    Api.send_error(conn, status, detail(changeset))
  end

  # Fields as the API names them.
  @fields %{payee_id: "payee_name"}

  defp detail(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&CoreComponents.translate_error/1)
    |> messages()
    |> Enum.uniq()
    |> Enum.join("; ")
  end

  defp messages(errors) do
    Enum.flat_map(errors, fn {field, entries} ->
      Enum.flat_map(entries, fn
        %{} = part -> part |> messages() |> Enum.map(&"#{field}: #{&1}")
        text -> ["#{Map.get(@fields, field, field)} #{text}"]
      end)
    end)
  end
end

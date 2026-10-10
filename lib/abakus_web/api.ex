defmodule AbakusWeb.Api do
  @moduledoc """
  The YNAB-compatible API under `/api/v1`, for the endpoints the shared-expenses app calls: YNAB's paths, field
  names, milliunits, `{"data": …}` envelopes and error format. The budget is the one plan, under a fixed id; all
  other ids are Abakus ids as strings. Error details are German, as the clients show them to their users.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Abakus.{Ledger, Schema}
  alias Abakus.Ledger.Account
  alias Plug.Conn.Status

  @plan_id "abakus"

  @errors %{
    400 => {"400", "bad_request"},
    401 => {"401", "not_authorized"},
    404 => {"404.2", "resource_not_found"},
    409 => {"409", "conflict"},
    500 => {"500", "internal_server_error"}
  }

  def plan_id, do: @plan_id

  @doc "Answers with YNAB's error format and halts."
  def send_error(conn, status, detail) do
    conn
    |> put_status(status)
    |> json(error_body(status, detail))
    |> halt()
  end

  @doc "YNAB's error body; a status YNAB does not document keeps its number and Plug's name for it."
  def error_body(status, detail) do
    {id, name} =
      Map.get_lazy(@errors, status, fn ->
        {Integer.to_string(status), Atom.to_string(Status.reason_atom(status))}
      end)

    %{error: %{id: id, name: name, detail: detail}}
  end

  def send_not_found(conn), do: send_error(conn, 404, "Nicht gefunden")

  @doc "The account with the id as a client sends it."
  def find_account(id) do
    with {:ok, id} <- Schema.cast_id(id),
         %Account{} = account <- Ledger.get_account(id) do
      {:ok, account}
    else
      _ -> {:error, :not_found}
    end
  end
end

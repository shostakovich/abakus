defmodule AbakusWeb.BankConsents do
  @moduledoc """
  The banner in Finanzen while a bank connection's consent ends within 14 days or has ended
  (`Abakus.BankSync.expiring_consents/1`), leading to Bankverbindungen to renew it. An `on_mount` hook assigns the
  connections as `@expiring_consents`, none for a user without the budget; the Bankverbindungen tab shows them on
  its cards instead.
  """
  use AbakusWeb, :html

  alias Abakus.{BankSync, Format}
  alias Abakus.BankSync.Connection
  alias AbakusWeb.Areas

  def on_mount(:assign, _params, _session, socket) do
    scope = socket.assigns.current_scope
    consents = if Areas.allowed?(scope, :budget), do: BankSync.expiring_consents(scope), else: []
    {:cont, Phoenix.Component.assign(socket, :expiring_consents, consents)}
  end

  attr :consents, :list, required: true, doc: "from `Abakus.BankSync.expiring_consents/1`"

  def banner(assigns) do
    ~H"""
    <.alert
      :if={@consents != []}
      id="bank-consent-banner"
      tone={:warning}
      title={title(@consents)}
      class="mb-6"
    >
      <p :for={connection <- @consents}>{consent_text(connection)}</p>
      <:actions>
        <.button size={:sm} icon="key-round" href={~p"/budget/bank-connections"}>
          Freigabe erneuern
        </.button>
      </:actions>
    </.alert>
    """
  end

  defp title([_one]), do: "Eine Bankfreigabe läuft aus"
  defp title(_several), do: "Bankfreigaben laufen aus"

  defp consent_text(connection) do
    if Connection.expired?(connection),
      do:
        "Die Freigabe für #{connection.bank_name} ist abgelaufen; Abakus ruft von dort nichts mehr ab.",
      else:
        "Die Freigabe für #{connection.bank_name} endet am #{Format.date(connection.valid_until)}."
  end
end

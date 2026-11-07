defmodule AbakusWeb.Bookkeeping.BusinessAccountsLive do
  @moduledoc """
  „Geschäftskonten“ in the settings, for everyone in Finanzen: which of their accounts are the business's, whose
  transactions the Buchhaltung's Posteingang asks a category for. The first one brings the Buchhaltung, the last one
  takes it away. Closed accounts show only while they are business accounts.
  """
  use AbakusWeb, :live_view

  alias Abakus.{Bookkeeping, Ledger}
  alias AbakusWeb.{Areas, NotFoundError, SettingsNav}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:business_accounts}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>Geschäftskonten</.header>
      <p class="mb-4 max-w-prose text-sm text-base-content/70">
        Die Buchungen dieser Konten erscheinen im Posteingang der Buchhaltung, bis sie eine Kategorie haben.
        Geschäftliche Ausgaben von anderen Konten bekommen ihre Kategorie im Konto selbst.
      </p>
      <.form for={%{}} id="business-accounts-form" phx-submit="save">
        <.input
          :for={account <- @accounts}
          id={"business-account-#{account.id}"}
          type="checkbox"
          name={"accounts[#{account.id}]"}
          label={account.name}
          checked={account.id in @business}
        />
        <p :if={@accounts == []} class="text-sm text-base-content/70">Noch keine Konten.</p>
        <.action_bar class="mt-4">
          <.button
            id="business-accounts-save"
            type="submit"
            variant={:primary}
            saved
            phx-disable-with="Speichert …"
          >
            Speichern
          </.button>
        </.action_bar>
      </.form>
    </Layouts.settings>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    Areas.allowed?(scope, :finanzen) || raise NotFoundError

    business = Bookkeeping.business_account_ids(scope)
    accounts = Enum.filter(Ledger.list_accounts(scope), &(not &1.closed or &1.id in business))

    {:ok, assign(socket, page_title: "Geschäftskonten", accounts: accounts, business: business)}
  end

  @impl true
  def handle_event("save", params, socket) do
    ids = for {id, "true"} <- Map.get(params, "accounts", %{}), do: id
    {:ok, business} = Bookkeeping.put_business_accounts(socket.assigns.current_scope, ids)

    {:noreply,
     socket
     |> assign(:business, business)
     |> Areas.keep_books(business != [])
     |> SettingsNav.assign_groups()
     |> push_saved("business-accounts-save")}
  end
end

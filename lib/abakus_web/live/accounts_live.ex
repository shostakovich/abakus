defmodule AbakusWeb.AccountsLive do
  @moduledoc """
  The account list (Konten) grouped into budget, tracking and closed accounts with working and cleared balance, the
  total and a way into the register of all accounts; each account leads to its register (`AbakusWeb.RegisterLive`).
  Adding an account opens `AbakusWeb.AccountDialog` over the list.
  """
  use AbakusWeb, :live_view

  alias AbakusWeb.{AccountGroups, Format}
  alias AbakusWeb.RegisterLive.Balances

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={:accounts}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <.account_list
        groups={@account_groups}
        total={Balances.all(AccountGroups.rows(@account_groups)).total}
      />
    </Layouts.app>
    """
  end

  attr :groups, :list, required: true
  attr :total, :integer, required: true

  defp account_list(assigns) do
    ~H"""
    <div class="app-narrow">
      <.header>
        Konten
        <:actions>
          <.button id="add-account" type="button" size="sm" phx-click="open_account_dialog">
            Konto hinzufügen
          </.button>
        </:actions>
      </.header>

      <p :if={@groups == []} class="text-body-secondary">Noch keine Konten.</p>

      <section :for={group <- @groups} id={"group-#{group.key}"} class="mb-4">
        <div class="d-flex justify-content-between align-items-baseline gap-2 mb-2">
          <h2 class="small text-uppercase fw-bold text-body-secondary mb-0">{group.label}</h2>
          <span
            id={"group-#{group.key}-balance"}
            class={["small fw-bold app-q", group.balance < 0 && "app-neg"]}
          >
            {Format.euros(group.balance)}
          </span>
        </div>
        <div class="list-group">
          <.link
            :for={row <- group.rows}
            id={"account-#{row.account.id}"}
            navigate={~p"/accounts/#{row.account}"}
            class="list-group-item list-group-item-action d-flex align-items-center gap-3"
          >
            <span class="me-auto app-min-w-0">
              <span class="d-block fw-semibold text-truncate">
                {row.account.name}
                <span
                  :if={row.unapproved > 0}
                  class="badge rounded-pill text-bg-primary"
                  title={"#{row.unapproved} zu bestätigen"}
                >
                  {row.unapproved}
                </span>
              </span>
              <span class="d-block small text-body-secondary text-truncate">
                {details(row.account)}
              </span>
            </span>
            <span class="text-end text-nowrap">
              <span
                id={"account-#{row.account.id}-balance"}
                class={["d-block fw-bold app-q", row.balance < 0 && "app-neg"]}
                title="Arbeitssaldo"
              >
                {Format.euros(row.balance)}
              </span>
              <span class="d-block small text-body-secondary">
                Abgeglichen
                <span id={"account-#{row.account.id}-cleared"} class="app-q">
                  {Format.euros(row.cleared)}
                </span>
              </span>
            </span>
          </.link>
        </div>
      </section>

      <div :if={@groups != []}>
        <div class="d-flex justify-content-between small text-uppercase fw-bold mb-3">
          <span>Gesamt</span>
          <span id="accounts-total" class={["app-q", @total < 0 && "app-neg"]}>
            {Format.euros(@total)}
          </span>
        </div>
        <.button variant="light" class="w-100" navigate={~p"/accounts/all"}>Alle Konten</.button>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Konten")}

  defp details(account),
    do:
      [AccountGroups.kind_label(account.kind), account.note]
      |> Enum.reject(&blank?/1)
      |> Enum.join(" · ")

  defp blank?(text), do: is_nil(text) or String.trim(text) == ""
end

defmodule AbakusWeb.AccountsLive do
  @moduledoc """
  The account list (Konten) grouped into budget, tracking and closed accounts with working and cleared balance, the
  total and a way into the register of all accounts; each account leads to its register (`AbakusWeb.RegisterLive`).
  Adding an account opens `AbakusWeb.AccountDialog` over the list.
  """
  use AbakusWeb, :live_view

  alias Abakus.Ledger.Account
  alias Abakus.Names
  alias AbakusWeb.{AccountGroups, AccountMotif}
  alias AbakusWeb.RegisterLive.Balances

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:accounts}
      width={:narrow}
      account_groups={@account_groups}
      depot_sidebar={@depot_sidebar}
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
    <.header>
      Konten
      <:actions :if={@groups != []}>
        <.button navigate={~p"/budget/accounts/all"} icon="landmark">Alle Konten</.button>
        <.button id="add-account" variant={:primary} icon="plus" phx-click="open_account_dialog">
          Konto hinzufügen
        </.button>
      </:actions>
    </.header>

    <.empty_state :if={@groups == []} plush="landmark" icon="landmark" title="Noch keine Konten">
      Lege ein Konto an, um Buchungen zu erfassen oder zu importieren.
      <:action>
        <.button id="add-account" variant={:primary} icon="plus" phx-click="open_account_dialog">
          Konto hinzufügen
        </.button>
      </:action>
    </.empty_state>

    <.list :if={@groups != []} id="accounts">
      <%= for group <- @groups do %>
        <.list_heading id={"group-#{group.key}"} class="flex items-baseline justify-between gap-4">
          <h2 class="text-sm">{group.label}</h2>
          <.amount
            id={"group-#{group.key}-balance"}
            value={group.balance}
            tone={:negative}
            class="text-sm"
          />
        </.list_heading>
        <.list_row
          :for={row <- group.rows}
          id={"account-#{row.account.id}"}
          navigate={~p"/budget/accounts/#{row.account}"}
          trailing_on_phone={:title}
        >
          <:leading><.figure account={row.account} /></:leading>
          {label(row.account.name)}
          <.badge :if={row.unapproved > 0} tone={:primary} class="ms-1.5 align-text-bottom">
            {row.unapproved} zu bestätigen
          </.badge>
          <:meta>{details(row.account)}</:meta>
          <:trailing :let={place}>
            <div class="flex flex-col items-end">
              <.amount
                id={balance_id(row, place, "balance")}
                value={row.balance}
                tone={:negative}
                class="font-medium"
                title="Arbeitssaldo"
              />
              <span class="text-sm text-base-content/70">
                Abgeglichen <.amount id={balance_id(row, place, "cleared")} value={row.cleared} />
              </span>
            </div>
          </:trailing>
        </.list_row>
      <% end %>
    </.list>

    <.description_list :if={@groups != []} class="mt-6">
      <:item label="Gesamt" total>
        <.amount id="accounts-total" value={@total} tone={:negative} />
      </:item>
    </.description_list>
    """
  end

  attr :account, Account, required: true

  defp figure(assigns) do
    assigns = assign(assigns, :glyph, glyph(assigns.account.name))

    ~H"""
    <span :if={@glyph} class="grid size-8 place-items-center text-2xl leading-none" aria-hidden="true">
      {@glyph}
    </span>
    <.plush :if={!@glyph} name={AccountMotif.for_account(@account)} size={:lg} />
    """
  end

  defp glyph(name), do: name |> Names.split_emoji() |> elem(0)
  defp label(name), do: name |> Names.split_emoji() |> elem(1)

  # The trailing balances render twice on phones (end of the title line) and from md (column).
  defp balance_id(row, :column, part), do: "account-#{row.account.id}-#{part}"
  defp balance_id(row, place, part), do: "account-#{row.account.id}-#{part}-#{place}"

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Konten")}

  defp details(account),
    do:
      join_meta([
        AccountGroups.kind_label(account.kind),
        account.note && String.trim(account.note)
      ])
end

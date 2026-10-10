defmodule AbakusWeb.AccountsLive do
  @moduledoc """
  The account list (Konten) grouped into budget, tracking and closed accounts with working and cleared balance, the
  total and a way into the register of all accounts; each account leads to its register (`AbakusWeb.RegisterLive`).
  And the form to add or edit an account: name, kind and note. Closing and reopening sit beside the edit form; accounts
  are never deleted. The kind stays on its side of the budget, so editing offers only that side's kinds.
  """
  use AbakusWeb, :live_view

  alias Abakus.Ledger
  alias Abakus.Ledger.Account
  alias AbakusWeb.{AccountGroups, Format}
  alias AbakusWeb.RegisterLive.Balances

  @editable ~w(name kind note)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={:accounts}
      account_groups={@account_groups}
    >
      <.account_list
        :if={@live_action == :index}
        groups={@account_groups}
        total={Balances.all(AccountGroups.rows(@account_groups)).total}
      />
      <.account_form
        :if={@live_action in [:new, :edit]}
        title={@page_title}
        form={@form}
        account={@account}
        balance={@balance}
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
          <.button size="sm" navigate={~p"/accounts/new"}>Konto hinzufügen</.button>
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

  attr :title, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :account, Account, required: true
  attr :balance, :integer, required: true

  defp account_form(assigns) do
    ~H"""
    <div class="app-narrow">
      <.link navigate={~p"/accounts"} class="d-inline-flex align-items-center gap-1 small mb-1">
        <.icon name="back" class="app-icon-sm" /> Konten
      </.link>
      <.header>{@title}</.header>

      <.card>
        <.form for={@form} id="account-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} label="Name" placeholder="z. B. 💶 Girokonto" required />
          <.input
            field={@form[:kind]}
            type="select"
            label="Art"
            options={kind_options(@account)}
            required
          />
          <p :if={is_nil(@account.id)} class="form-text mt-n2 mb-3">
            Tracking-Konten wie ein Depot zählen nicht zum Budget. Das lässt sich später nicht ändern.
          </p>
          <.input field={@form[:note]} type="textarea" label="Notiz" rows="2" />
          <div class="d-flex gap-2">
            <.button type="submit" phx-disable-with="Speichern …">Speichern</.button>
            <.button variant="outline-secondary" navigate={~p"/accounts"}>Abbrechen</.button>
          </div>
        </.form>
      </.card>

      <.card :if={@account.id && !@account.closed} title="Konto schließen" level={2}>
        <p class="text-body-secondary">
          Ein geschlossenes Konto verschwindet aus der Seitenleiste. Seine Buchungen bleiben.
        </p>
        <.button
          id="close-account"
          variant="outline-danger"
          phx-click="close"
          data-confirm={close_question(@account, @balance)}
        >
          Konto schließen
        </.button>
      </.card>

      <.card :if={@account.id && @account.closed} title="Geschlossen" level={2}>
        <p class="text-body-secondary">Dieses Konto ist geschlossen.</p>
        <.button id="reopen-account" variant="outline-primary" phx-click="reopen">
          Wieder öffnen
        </.button>
      </.card>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _url, socket),
    do: {:noreply, apply_action(socket, socket.assigns.live_action, params)}

  defp apply_action(socket, :index, _params), do: assign(socket, :page_title, "Konten")

  defp apply_action(socket, :new, _params),
    do: socket |> assign(:page_title, "Konto hinzufügen") |> edit(%Account{kind: :checking})

  defp apply_action(socket, :edit, %{"id" => id}),
    do: socket |> assign(:page_title, "Konto bearbeiten") |> edit(Ledger.get_account!(id))

  defp edit(socket, account) do
    socket
    |> assign(account: account, balance: balance(socket.assigns.account_groups, account))
    |> assign(:form, to_form(Ledger.change_account(account)))
  end

  @impl true
  def handle_event("validate", %{"account" => params}, socket) do
    changeset = Ledger.change_account(socket.assigns.account, editable(params))
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"account" => params}, socket) do
    case save(socket.assigns.account, editable(params)) do
      {:ok, _account} ->
        {:noreply, done(socket, saved(socket.assigns.account))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("close", _params, socket), do: set_closed(socket, true, "Konto geschlossen.")

  def handle_event("reopen", _params, socket),
    do: set_closed(socket, false, "Konto wieder geöffnet.")

  defp save(%Account{id: nil}, params), do: Ledger.create_account(params)
  defp save(account, params), do: Ledger.update_account(account, params)

  defp saved(%Account{id: nil}), do: "Konto angelegt."
  defp saved(_account), do: "Konto gespeichert."

  defp set_closed(socket, closed, message) do
    {:ok, _account} = Ledger.update_account(socket.assigns.account, %{closed: closed})
    {:noreply, done(socket, message)}
  end

  defp done(socket, message),
    do: socket |> put_flash(:info, message) |> push_navigate(to: ~p"/accounts")

  # The form edits only these; closing has its own buttons, position and feeds are not the user's to set here.
  defp editable(params), do: Map.take(params, @editable)

  defp kind_options(%Account{id: nil}), do: options(AccountGroups.kinds())

  defp kind_options(account) do
    budget? = Account.budget_account?(account)

    AccountGroups.kinds()
    |> Enum.filter(fn {kind, _} -> kind in Account.budget_kinds() == budget? end)
    |> options()
  end

  defp options(kinds), do: Enum.map(kinds, fn {kind, label} -> {label, kind} end)

  defp details(account),
    do:
      [AccountGroups.kind_label(account.kind), account.note]
      |> Enum.reject(&blank?/1)
      |> Enum.join(" · ")

  defp blank?(text), do: is_nil(text) or String.trim(text) == ""

  defp balance(groups, account) do
    Enum.find_value(groups, 0, fn group ->
      Enum.find_value(group.rows, &(&1.account.id == account.id && &1.balance))
    end)
  end

  defp close_question(account, 0), do: "Konto „#{account.name}“ schließen?"

  defp close_question(account, balance),
    do: "#{close_question(account, 0)} Es hat noch einen Saldo von #{Format.euros(balance)}."
end

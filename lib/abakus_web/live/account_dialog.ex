defmodule AbakusWeb.AccountDialog do
  @moduledoc """
  The account form as in YNAB, a modal over the current page (on phones a sheet from the bottom). Adding asks for
  name, kind and the current balance, which is booked today as "Anfangssaldo" (`Abakus.Ledger.create_account/3`);
  it may add and subtract as the register's amounts do. Editing takes name and kind, with "Konto schließen …" bottom
  left; accounts are never deleted, and a closed one is opened again in its register, or here with `reopenable` for
  one no register shows. The kind stays on its side of the budget, so editing offers only that side's kinds, and
  none to pick for a tracking account.

  Every signed-in page of the budget owner has it through `on_mount(:attach, …)`: the event `open_account_dialog`
  opens it, with `id` to edit that account, without to add one; `close_account_dialog` closes it. `Layouts.app`
  renders it from `account_dialog`. A new account opens its register; after an edit or closing, the page stays as it
  is and runs its URL's params again, so it shows the account as it is now. The Depot's settings
  (`AbakusWeb.Depot.PortfoliosLive`) render it themselves for a portfolio's cash, which no register shows.
  """
  use AbakusWeb, :live_component

  alias Abakus.{Amount, Ledger, LocalTime, Money}
  alias Abakus.Ledger.Account
  alias AbakusWeb.AccountGroups

  @editable ~w(name kind)

  def on_mount(:attach, _params, _session, socket) do
    if AbakusWeb.Areas.allowed?(socket.assigns.current_scope, :budget),
      do: {:cont, attach(socket)},
      else: {:cont, assign(socket, account_dialog: nil)}
  end

  defp attach(socket) do
    socket
    |> assign(account_dialog: nil, account_dialog_path: nil)
    |> attach_hook(:account_dialog_path, :handle_params, fn _params, uri, socket ->
      {:cont, assign(socket, :account_dialog_path, path(URI.parse(uri)))}
    end)
    |> attach_hook(:account_dialog, :handle_event, &handle_page_event/3)
    |> attach_hook(:account_dialog_done, :handle_info, &handle_page_info/2)
  end

  defp handle_page_event("open_account_dialog", params, socket),
    do: {:halt, assign(socket, :account_dialog, opened(params, socket.assigns.account_groups))}

  defp handle_page_event("close_account_dialog", _params, socket),
    do: {:halt, assign(socket, :account_dialog, nil)}

  defp handle_page_event(_event, _params, socket), do: {:cont, socket}

  defp handle_page_info({__MODULE__, :done, message, result}, socket) do
    socket =
      socket
      |> assign(
        account_dialog: nil,
        account_groups: AccountGroups.load(socket.assigns.current_scope)
      )
      |> clear_flash()
      |> put_flash(:info, message)

    {:halt, after_done(socket, result)}
  end

  defp handle_page_info(_message, socket), do: {:cont, socket}

  defp opened(%{"id" => id}, groups) do
    case Enum.find(AccountGroups.rows(groups), &(&1.account.id == id)) do
      nil -> nil
      row -> %{account: row.account, balance: row.balance}
    end
  end

  defp opened(_params, _groups), do: %{account: %Account{kind: :checking}, balance: 0}

  defp after_done(socket, {:created, account}),
    do: push_navigate(socket, to: ~p"/budget/accounts/#{account}")

  defp after_done(%{assigns: %{account_dialog_path: nil}} = socket, :changed), do: socket

  defp after_done(socket, :changed),
    do: push_patch(socket, to: socket.assigns.account_dialog_path)

  defp path(%URI{path: path, query: nil}), do: path
  defp path(%URI{path: path, query: query}), do: path <> "?" <> query

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :kinds, kind_options(assigns.account))

    ~H"""
    <div id={@id}>
      <.modal
        id="account-dialog-modal"
        show
        title={if @account.id, do: "Konto bearbeiten", else: "Konto hinzufügen"}
        on_cancel={JS.push("close_account_dialog")}
      >
        <.form
          for={@form}
          id="account-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
        >
          <.alert :if={@reopenable && @account.closed} id="account-closed" tone={:neutral}>
            Dieses Konto ist geschlossen.
          </.alert>
          <.input
            field={@form[:name]}
            label="Name"
            placeholder="z. B. 💶 Girokonto"
            autocomplete="off"
            required
          />
          <div :if={is_nil(@account.id)} class="grid gap-x-4 sm:grid-cols-2">
            <.input
              field={@form[:kind]}
              type="select"
              label="Art"
              options={@kinds}
              required
            />
            <.input
              field={@form[:balance]}
              label="Aktueller Saldo"
              placeholder="0,00"
              suffix="€"
              numeric
              autocomplete="off"
            />
          </div>
          <p :if={is_nil(@account.id)} id="account-kind-hint" class="text-sm text-base-content/70">
            Tracking-Konten zählen nicht zum Budget. Das lässt sich später nicht ändern.
          </p>
          <.input
            :if={@account.id && length(@kinds) > 1}
            field={@form[:kind]}
            type="select"
            label="Art"
            options={@kinds}
            required
          />
          <.action_bar>
            <:secondary :if={@account.id && (!@account.closed || @reopenable)}>
              <.button
                :if={@reopenable && @account.closed}
                id="reopen-account"
                phx-click="reopen"
                phx-target={@myself}
              >
                Wieder öffnen
              </.button>
              <.button
                :if={!@account.closed}
                id="close-account"
                variant={:ghost}
                class="text-error-ink"
                phx-click="close"
                phx-target={@myself}
                confirm={"Konto „#{@account.name}“ schließen?"}
                confirm_text={close_text(@balance)}
                confirm_label="Schließen"
              >
                Konto schließen …
              </.button>
            </:secondary>
            <.button id="account-cancel" phx-click="close_account_dialog">Abbrechen</.button>
            <.button
              id="account-save"
              type="submit"
              variant={:primary}
              phx-disable-with={if @account.id, do: "Speichern …", else: "Hinzufügen …"}
            >
              {if @account.id, do: "Speichern", else: "Hinzufügen"}
            </.button>
          </.action_bar>
        </.form>
      </.modal>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    key = assigns.account.id
    socket = socket |> assign(:reopenable, false) |> assign(assigns)

    if Map.get(socket.assigns, :loaded) == {key},
      do: {:ok, socket},
      else:
        {:ok,
         assign(socket, loaded: {key}, form: to_form(Ledger.change_account(assigns.account)))}
  end

  @impl true
  def handle_event("validate", %{"account" => params}, socket) do
    changeset =
      socket.assigns.account
      |> Ledger.change_account(form_params(params))
      |> validate_balance()

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"account" => params}, socket) do
    case save(socket.assigns.current_scope, socket.assigns.account, params) do
      {:ok, account} ->
        {:noreply, saved(socket, account)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(keep_typed(changeset, params)))}
    end
  end

  def handle_event("close", _params, socket), do: set_closed(socket, true, "Konto geschlossen.")

  def handle_event("reopen", _params, %{assigns: %{reopenable: true}} = socket),
    do: set_closed(socket, false, "Konto wieder geöffnet.")

  defp set_closed(socket, closed, message) do
    %{current_scope: current_scope, account: account} = socket.assigns
    {:ok, _account} = Ledger.update_account(current_scope, account, %{closed: closed})
    {:noreply, done(socket, message, :changed)}
  end

  defp save(current_scope, %Account{id: nil} = account, params) do
    case balance(params) do
      {:ok, balance} ->
        Ledger.create_account(current_scope, editable(params),
          balance: balance,
          date: LocalTime.today()
        )

      {:error, _message} ->
        {:error,
         account |> Ledger.change_account(form_params(params)) |> validate_balance() |> failed()}
    end
  end

  defp save(current_scope, account, params),
    do: Ledger.update_account(current_scope, account, editable(params))

  defp failed(changeset), do: %{changeset | action: :insert}

  defp keep_typed(changeset, params),
    do: %{changeset | params: Map.merge(changeset.params || %{}, form_params(params))}

  defp form_params(params), do: Map.take(params, ["balance" | @editable])

  defp validate_balance(changeset) do
    case balance(changeset.params) do
      {:ok, _balance} -> changeset
      {:error, message} -> Ecto.Changeset.add_error(changeset, :balance, message)
    end
  end

  defp balance(params) do
    with {:ok, cents} <- parse_balance(params["balance"]) do
      if Amount.valid?(cents), do: {:ok, cents}, else: {:error, Amount.out_of_range_message()}
    end
  end

  defp parse_balance(text) do
    case String.trim(text || "") do
      "" -> {:ok, 0}
      text -> Money.parse_expression(text, 2)
    end
  end

  defp saved(%{assigns: %{account: %Account{id: nil}}} = socket, account),
    do: done(socket, "Konto angelegt.", {:created, account})

  defp saved(socket, _account), do: done(socket, "Konto gespeichert.", :changed)

  defp done(socket, message, result) do
    send(self(), {__MODULE__, :done, message, result})
    socket
  end

  # Closing has its own button; position and the shared-expenses mark are not the user's to set here.
  defp editable(params), do: Map.take(params, @editable)

  defp kind_options(%Account{id: nil}), do: options(AccountGroups.kinds())

  defp kind_options(account) do
    budget? = Account.budget_account?(account)

    AccountGroups.kinds()
    |> Enum.filter(fn {kind, _} -> kind in Account.budget_kinds() == budget? end)
    |> options()
  end

  defp options(kinds), do: Enum.map(kinds, fn {kind, label} -> {label, kind} end)

  defp close_text(0), do: "Du kannst es später wieder öffnen."
  defp close_text(balance), do: "Es hat noch einen Saldo von #{Money.euros(balance)}."
end

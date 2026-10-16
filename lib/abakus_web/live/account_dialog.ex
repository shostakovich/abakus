defmodule AbakusWeb.AccountDialog do
  @moduledoc """
  The account form as in YNAB, a modal over the current page (on phones a sheet from the bottom): name, kind and
  note. Closing or reopening sits bottom left; accounts are never deleted. The kind stays on its side of the budget,
  so editing offers only that side's kinds, and none to pick for a tracking account.

  Every signed-in page of the budget owner has it through `on_mount(:attach, …)`: the event `open_account_dialog`
  opens it, with `id` to edit that account, without to add one; `close_account_dialog` closes it. `Layouts.app`
  renders it from `account_dialog`. A new account opens its register; after an edit or closing, the page stays as it
  is and runs its URL's params again, so it shows the account as it is now.
  """
  use AbakusWeb, :live_component

  alias Abakus.Ledger
  alias Abakus.Ledger.Account
  alias Abakus.Money
  alias AbakusWeb.AccountGroups

  @editable ~w(name kind note)

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
      |> assign(account_dialog: nil, account_groups: AccountGroups.load())
      |> clear_flash()
      |> put_flash(:info, message)

    {:halt, after_done(socket, result)}
  end

  defp handle_page_info(_message, socket), do: {:cont, socket}

  defp opened(%{"id" => id}, groups) do
    case Enum.find(AccountGroups.rows(groups), &(Integer.to_string(&1.account.id) == id)) do
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
          <.alert :if={@account.closed} id="account-closed" tone={:neutral}>
            Dieses Konto ist geschlossen.
          </.alert>
          <.input
            field={@form[:name]}
            label="Name"
            placeholder="z. B. 💶 Girokonto"
            autocomplete="off"
            required
          />
          <.input
            :if={length(@kinds) > 1}
            field={@form[:kind]}
            type="select"
            label="Art"
            options={@kinds}
            help={
              if is_nil(@account.id),
                do:
                  "Tracking-Konten wie ein Depot zählen nicht zum Budget. Das lässt sich später nicht ändern."
            }
            required
          />
          <.input field={@form[:note]} type="textarea" label="Notiz" rows="2" />
          <.action_bar>
            <:secondary :if={@account.id}>
              <.button
                :if={!@account.closed}
                id="close-account"
                variant={:danger_outline}
                phx-click="close"
                phx-target={@myself}
                confirm={"Konto „#{@account.name}“ schließen?"}
                confirm_text={close_text(@balance)}
                confirm_label="Schließen"
              >
                Konto schließen
              </.button>
              <.button
                :if={@account.closed}
                id="reopen-account"
                phx-click="reopen"
                phx-target={@myself}
              >
                Wieder öffnen
              </.button>
            </:secondary>
            <.button id="account-cancel" phx-click="close_account_dialog">Abbrechen</.button>
            <.button
              id="account-save"
              type="submit"
              variant={:primary}
              phx-disable-with="Speichern …"
            >
              Speichern
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
    socket = assign(socket, assigns)

    if Map.get(socket.assigns, :loaded) == {key},
      do: {:ok, socket},
      else:
        {:ok,
         assign(socket, loaded: {key}, form: to_form(Ledger.change_account(assigns.account)))}
  end

  @impl true
  def handle_event("validate", %{"account" => params}, socket) do
    changeset = Ledger.change_account(socket.assigns.account, editable(params))
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"account" => params}, socket) do
    case save(socket.assigns.account, editable(params)) do
      {:ok, account} -> {:noreply, saved(socket, account)}
      {:error, changeset} -> {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("close", _params, socket), do: set_closed(socket, true, "Konto geschlossen.")

  def handle_event("reopen", _params, socket),
    do: set_closed(socket, false, "Konto wieder geöffnet.")

  defp save(%Account{id: nil}, params), do: Ledger.create_account(params)
  defp save(account, params), do: Ledger.update_account(account, params)

  defp saved(%{assigns: %{account: %Account{id: nil}}} = socket, account),
    do: done(socket, "Konto angelegt.", {:created, account})

  defp saved(socket, _account), do: done(socket, "Konto gespeichert.", :changed)

  defp set_closed(socket, closed, message) do
    {:ok, _account} = Ledger.update_account(socket.assigns.account, %{closed: closed})
    {:noreply, done(socket, message, :changed)}
  end

  defp done(socket, message, result) do
    send(self(), {__MODULE__, :done, message, result})
    socket
  end

  # Closing has its own buttons; position and feeds are not the user's to set here.
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

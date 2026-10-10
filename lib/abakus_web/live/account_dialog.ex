defmodule AbakusWeb.AccountDialog do
  @moduledoc """
  The account form as in YNAB, a modal over the current page (on phones a sheet from the bottom): name, kind and
  note. Closing or reopening sits bottom left; accounts are never deleted. The kind stays on its side of the budget,
  so editing offers only that side's kinds, and none to pick for a tracking account.

  Every signed-in page has it through `on_mount(:attach, …)`: the event `open_account_dialog` opens it, with
  `id` to edit that account, without to add one; `close_account_dialog` closes it. `Layouts.app` renders it from
  `account_dialog`. A new account opens its register; after an edit or closing, the page stays as it is and runs
  its URL's params again, so it shows the account as it is now.
  """
  use AbakusWeb, :live_component

  alias Abakus.Ledger
  alias Abakus.Ledger.Account
  alias AbakusWeb.{AccountGroups, Format}

  @editable ~w(name kind note)

  def on_mount(:attach, _params, _session, socket) do
    {:cont,
     socket
     |> assign(account_dialog: nil, account_dialog_path: nil)
     |> attach_hook(:account_dialog_path, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :account_dialog_path, path(URI.parse(uri)))}
     end)
     |> attach_hook(:account_dialog, :handle_event, &handle_page_event/3)
     |> attach_hook(:account_dialog_done, :handle_info, &handle_page_info/2)}
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
    do: push_navigate(socket, to: ~p"/accounts/#{account}")

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
      <div class="modal-backdrop show"></div>
      <div
        class="modal d-block app-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="account-dialog-title"
        phx-window-keydown="close_account_dialog"
        phx-key="Escape"
      >
        <div class="modal-dialog modal-dialog-scrollable app-sheet">
          <.form
            for={@form}
            id="account-form"
            class="modal-content"
            phx-change="validate"
            phx-submit="save"
            phx-target={@myself}
            phx-mounted={JS.focus(to: "#account_name")}
          >
            <div class="modal-header">
              <h2 class="modal-title h5" id="account-dialog-title">
                {if @account.id, do: "Konto bearbeiten", else: "Konto hinzufügen"}
              </h2>
              <button
                id="account-dialog-x"
                type="button"
                class="btn-close"
                aria-label="Schließen"
                phx-click="close_account_dialog"
              ></button>
            </div>
            <div class="modal-body">
              <div :if={@account.closed} id="account-closed" class="alert alert-secondary small py-2">
                Dieses Konto ist geschlossen.
              </div>
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
                required
                wrapper_class={if(@account.id, do: "mb-3", else: "mb-1")}
              />
              <p :if={is_nil(@account.id)} class="form-text mt-0 mb-3">
                Tracking-Konten wie ein Depot zählen nicht zum Budget. Das lässt sich später nicht ändern.
              </p>
              <.input field={@form[:note]} type="textarea" label="Notiz" rows="2" wrapper_class="" />
            </div>
            <div class="modal-footer">
              <button
                :if={@account.id && !@account.closed}
                id="close-account"
                type="button"
                class="btn btn-outline-danger me-auto"
                phx-click="close"
                phx-target={@myself}
                data-confirm={close_question(@account, @balance)}
              >
                Konto schließen
              </button>
              <button
                :if={@account.id && @account.closed}
                id="reopen-account"
                type="button"
                class="btn btn-outline-primary me-auto"
                phx-click="reopen"
                phx-target={@myself}
              >
                Wieder öffnen
              </button>
              <%!-- Phones close the sheet with the ×; three buttons do not fit side by side there. --%>
              <button
                id="account-cancel"
                type="button"
                class="btn d-none d-sm-inline-block"
                phx-click="close_account_dialog"
              >
                Abbrechen
              </button>
              <button
                id="account-save"
                type="submit"
                class="btn btn-primary"
                phx-disable-with="Speichern …"
              >
                Speichern
              </button>
            </div>
          </.form>
        </div>
      </div>
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

  defp close_question(account, 0), do: "Konto „#{account.name}“ schließen?"

  defp close_question(account, balance),
    do: "#{close_question(account, 0)} Es hat noch einen Saldo von #{Format.euros(balance)}."
end

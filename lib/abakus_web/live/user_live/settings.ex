defmodule AbakusWeb.UserLive.Settings do
  use AbakusWeb, :live_view

  on_mount {AbakusWeb.UserAuth, :require_sudo_mode}

  alias Abakus.{ApiTokens, Users}
  alias AbakusWeb.Format

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={:settings}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <.header>Einstellungen</.header>

      <div class="row g-4">
        <div class="col-lg-7">
          <.card title="Passkeys" id="passkeys">
            <p class="text-body-secondary">
              Mit einem Passkey meldest du dich per Face ID, Fingerabdruck oder Geräte-PIN an.
            </p>
            <p :if={@passkeys == []} class="fst-italic">Noch kein Passkey hinterlegt.</p>
            <ul :if={@passkeys != []} class="list-group mb-3">
              <li
                :for={passkey <- @passkeys}
                id={"passkey-#{passkey.id}"}
                class="list-group-item d-flex align-items-center gap-2"
              >
                <div class="me-auto">
                  <div class="fw-semibold">{passkey.name}</div>
                  <div class="small text-body-secondary">
                    angelegt {Format.date(DateTime.to_date(passkey.inserted_at))}
                    <span :if={passkey.last_used_at}>
                      · zuletzt genutzt {Format.date(DateTime.to_date(passkey.last_used_at))}
                    </span>
                  </div>
                </div>
                <.button
                  variant="outline-danger"
                  size="sm"
                  phx-click="delete_passkey"
                  phx-value-id={passkey.id}
                  data-confirm={"Passkey „#{passkey.name}“ löschen?"}
                >
                  Löschen
                </.button>
              </li>
            </ul>
            <%!-- The hook owns this form; ignored on re-render, so an error keeps the typed name. --%>
            <form id="passkey-register" phx-hook="PasskeyRegister" phx-update="ignore">
              <label class="form-label" for="passkey-name">Name des neuen Passkeys</label>
              <div class="d-flex flex-column flex-sm-row gap-2">
                <input
                  id="passkey-name"
                  name="name"
                  class="form-control"
                  placeholder="z. B. iPhone"
                  maxlength="60"
                  required
                />
                <button class="btn btn-primary text-nowrap" type="submit">
                  Passkey hinzufügen
                </button>
              </div>
            </form>
          </.card>

          <.card title="API-Tokens" id="api-tokens">
            <p class="text-body-secondary">
              YNAB-kompatible API, z. B. für eine Ausgaben-App: dieselben Pfade wie bei YNAB
              (<code>/plans/{"{plan_id}"}/transactions</code>) unter dieser Basis-URL.
            </p>
            <.input
              id="api-base-url"
              name="api-base-url"
              label="Basis-URL"
              value={url(~p"/api/v1")}
              class="font-monospace"
              readonly
            />
            <p :if={@api_tokens == []} class="fst-italic">Noch kein Token angelegt.</p>
            <ul :if={@api_tokens != []} class="list-group mb-3">
              <li
                :for={api_token <- @api_tokens}
                id={"api-token-#{api_token.id}"}
                class="list-group-item d-flex align-items-center gap-2"
              >
                <div class="me-auto">
                  <div class="fw-semibold">{api_token.name}</div>
                  <div class="small text-body-secondary">
                    erstellt {Format.date(DateTime.to_date(api_token.inserted_at))} · {last_used(
                      api_token
                    )}
                  </div>
                </div>
                <.button
                  variant="outline-danger"
                  size="sm"
                  phx-click="revoke_api_token"
                  phx-value-id={api_token.id}
                  data-confirm={"Token „#{api_token.name}“ widerrufen? Programme mit diesem Token verlieren den Zugriff sofort."}
                >
                  Widerrufen
                </.button>
              </li>
            </ul>
            <div :if={@new_api_token} id="new-api-token" class="alert alert-success" role="status">
              Neues Token, wird nur jetzt angezeigt:<br />
              <code class="user-select-all text-break">{@new_api_token}</code>
            </div>
            <.form for={@api_token_form} id="api-token-form" phx-submit="create_api_token">
              <.input
                field={@api_token_form[:name]}
                label="Name des neuen Tokens"
                placeholder="z. B. Zipfelkasse"
                maxlength="60"
                required
              />
              <.button phx-disable-with="Wird erstellt …">Token erstellen</.button>
            </.form>
          </.card>
        </div>

        <div class="col-lg-5">
          <.card title="E-Mail-Adresse">
            <.form
              for={@email_form}
              id="email-form"
              phx-submit="update_email"
              phx-change="validate_email"
            >
              <.input
                field={@email_form[:email]}
                type="email"
                label="E-Mail"
                autocomplete="username"
                spellcheck="false"
                required
              />
              <.button phx-disable-with="Wird gesendet …">E-Mail ändern</.button>
            </.form>
          </.card>

          <.card title="Aussehen" id="appearance">
            <p class="text-body-secondary">Gilt für dieses Gerät.</p>
            <Layouts.theme_switch />
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Users.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} -> put_flash(socket, :info, "Die E-Mail-Adresse ist geändert.")
        {:error, _} -> put_flash(socket, :error, "Der Link ist ungültig oder abgelaufen.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user
    token = session["user_token"]

    {:ok,
     socket
     |> assign(:page_title, "Einstellungen")
     |> assign(
       :email_form,
       to_form(Users.change_user_email(user, %{}, validate_unique: false))
     )
     |> assign_passkeys()
     |> assign(:new_api_token, nil)
     |> assign(:api_token_form, to_form(ApiTokens.change_api_token()))
     |> assign_api_tokens()
     |> attach_hook(:sudo_mode, :handle_event, &require_sudo_mode(&1, &2, &3, token))}
  end

  # The page may stay open past the sudo window or the session; changes check both again.
  defp require_sudo_mode(event, _params, socket, token)
       when event in ["update_email", "delete_passkey", "create_api_token", "revoke_api_token"] do
    with true <- is_binary(token),
         {user, _token_inserted_at} <- Users.get_user_by_session_token(token),
         true <- Users.sudo_mode?(user) do
      {:cont, socket}
    else
      # Through the page's plug, which sends the user to sign in and back.
      _ -> {:halt, redirect(socket, to: ~p"/users/settings")}
    end
  end

  defp require_sudo_mode(_event, _params, socket, _token), do: {:cont, socket}

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Users.change_user_email(user_params, validate_unique: false)
      |> to_form(action: :validate)

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    case Users.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Users.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        {:noreply,
         put_flash(
           socket,
           :info,
           "Wir haben einen Bestätigungslink an die neue Adresse geschickt."
         )}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("passkey_registered", _params, socket) do
    {:noreply, socket |> put_flash(:info, "Passkey hinzugefügt.") |> assign_passkeys()}
  end

  def handle_event("passkey_error", %{"message" => message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_event("delete_passkey", %{"id" => id}, socket) do
    case Users.delete_passkey(socket.assigns.current_scope.user, id) do
      {:ok, _passkey} ->
        {:noreply, socket |> put_flash(:info, "Passkey gelöscht.") |> assign_passkeys()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Den Passkey gibt es nicht mehr.")}
    end
  end

  def handle_event("create_api_token", %{"api_token" => attrs}, socket) do
    case ApiTokens.create_api_token(attrs) do
      {:ok, token, _api_token} ->
        {:noreply,
         socket
         |> assign(:new_api_token, token)
         |> assign(:api_token_form, to_form(ApiTokens.change_api_token()))
         |> assign_api_tokens()}

      {:error, changeset} ->
        {:noreply, assign(socket, :api_token_form, to_form(changeset, action: :insert))}
    end
  end

  # Also hides the token shown once, which may be the one revoked.
  def handle_event("revoke_api_token", %{"id" => id}, socket) do
    case ApiTokens.revoke_api_token(id) do
      {:ok, _api_token} ->
        {:noreply,
         socket
         |> put_flash(:info, "Token widerrufen.")
         |> assign(:new_api_token, nil)
         |> assign_api_tokens()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Das Token gibt es nicht mehr.")}
    end
  end

  defp assign_api_tokens(socket), do: assign(socket, :api_tokens, ApiTokens.list_api_tokens())

  defp last_used(%{last_used_at: nil}), do: "nie genutzt"

  defp last_used(%{last_used_at: used_at}),
    do: "zuletzt genutzt #{Format.date(DateTime.to_date(used_at))}"

  defp assign_passkeys(socket),
    do: assign(socket, :passkeys, Users.list_passkeys(socket.assigns.current_scope.user))
end

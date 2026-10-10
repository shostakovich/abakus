defmodule AbakusWeb.UserLive.Settings do
  use AbakusWeb, :live_view

  on_mount {AbakusWeb.UserAuth, :require_sudo_mode}

  alias Abakus.Users
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
     |> attach_hook(:sudo_mode, :handle_event, &require_sudo_mode(&1, &2, &3, token))}
  end

  # The page may stay open past the sudo window or the session; changes check both again.
  defp require_sudo_mode(event, _params, socket, token)
       when event in ["update_email", "delete_passkey"] do
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

  defp assign_passkeys(socket),
    do: assign(socket, :passkeys, Users.list_passkeys(socket.assigns.current_scope.user))
end

defmodule AbakusWeb.UserLive.Settings do
  use AbakusWeb, :live_view

  on_mount {AbakusWeb.UserAuth, :require_sudo_mode}

  alias Abakus.Users
  alias AbakusWeb.Format
  alias AbakusWeb.SettingsLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <Components.page
      section={:access}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <div class="flex flex-col gap-8">
        <section id="passkeys" aria-labelledby="passkeys-title">
          <.section_heading id="passkeys-title" count={if @passkeys != [], do: length(@passkeys)}>
            Passkeys
          </.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Mit einem Passkey meldest du dich per Face ID, Fingerabdruck oder Geräte-PIN an.
          </p>
          <.empty_state :if={@passkeys == []} icon="key-round">
            Noch kein Passkey hinterlegt.
          </.empty_state>
          <.list :if={@passkeys != []}>
            <.list_row
              :for={passkey <- @passkeys}
              id={"passkey-#{passkey.id}"}
              title={passkey.name}
            >
              <:leading><.icon name="key-round" class="size-5 text-base-content/70" /></:leading>
              <:meta>
                angelegt {Format.date(DateTime.to_date(passkey.inserted_at))}<span :if={
                  passkey.last_used_at
                }><.meta_sep />zuletzt genutzt {Format.date(DateTime.to_date(passkey.last_used_at))}</span>
              </:meta>
              <:action
                id={"passkey-#{passkey.id}-delete"}
                label="Löschen"
                icon="trash-2"
                danger
                confirm={"Passkey „#{passkey.name}“ löschen?"}
                on_click={JS.push("delete_passkey", value: %{id: passkey.id})}
              />
            </.list_row>
          </.list>
          <%!-- The hook owns this form; ignored on re-render, so an error keeps the typed name. --%>
          <form id="passkey-register" class="mt-4" phx-hook="PasskeyRegister" phx-update="ignore">
            <.input
              id="passkey-name"
              name="name"
              label="Name des neuen Passkeys"
              placeholder="Name, z. B. iPhone"
              maxlength="60"
              inline
              required
            >
              <.button type="submit" variant={:primary} icon="plus" class="join-item">
                Passkey hinzufügen
              </.button>
            </.input>
          </form>
        </section>

        <section id="email" aria-labelledby="email-title">
          <.section_heading id="email-title">E-Mail-Adresse</.section_heading>
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
              inline
              required
            >
              <.button type="submit" class="join-item" phx-disable-with="Wird gesendet …">
                E-Mail ändern
              </.button>
            </.input>
          </.form>
        </section>
      </div>
    </Components.page>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Users.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} -> put_flash(socket, :info, "Die E-Mail-Adresse ist geändert.")
        {:error, _} -> put_flash(socket, :error, "Der Link ist ungültig oder abgelaufen.")
      end

    {:ok, push_navigate(socket, to: ~p"/settings/access")}
  end

  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user
    token = session["user_token"]

    {:ok,
     socket
     |> assign(:page_title, Components.label(:access))
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
      _ -> {:halt, redirect(socket, to: ~p"/settings/access")}
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

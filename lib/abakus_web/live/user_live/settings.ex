defmodule AbakusWeb.UserLive.Settings do
  use AbakusWeb, :live_view

  on_mount {AbakusWeb.UserAuth, :require_sudo_mode}

  alias Abakus.{ApiTokens, Users}
  alias AbakusWeb.Format
  alias AbakusWeb.SettingsLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <Components.page
      section={:access}
      flash={@flash}
      current_scope={@current_scope}
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

        <section id="api-tokens" aria-labelledby="api-tokens-title">
          <.section_heading
            id="api-tokens-title"
            count={if @api_tokens != [], do: length(@api_tokens)}
          >
            API-Tokens
          </.section_heading>
          <p class="max-w-prose text-sm text-base-content/70">
            YNAB-kompatible API, z. B. für eine Ausgaben-App: dieselben Pfade wie bei YNAB
            (<code>/plans/{"{plan_id}"}/transactions</code>) unter dieser Basis-URL.
          </p>
          <.input
            id="api-base-url"
            name="api-base-url"
            label="Basis-URL"
            value={url(~p"/api/v1")}
            class="font-mono"
            readonly
          />
          <.empty_state :if={@api_tokens == []} icon="key-round">
            Noch kein Token angelegt.
          </.empty_state>
          <.list :if={@api_tokens != []} class="mt-4">
            <.list_row
              :for={api_token <- @api_tokens}
              id={"api-token-#{api_token.id}"}
              title={api_token.name}
            >
              <:meta>
                {join_meta([
                  "erstellt #{Format.date(DateTime.to_date(api_token.inserted_at))}",
                  last_used(api_token)
                ])}
              </:meta>
              <:action
                id={"api-token-#{api_token.id}-revoke"}
                label="Widerrufen"
                icon="trash-2"
                danger
                confirm={"Token „#{api_token.name}“ widerrufen?"}
                confirm_text="Programme mit diesem Token verlieren den Zugriff sofort."
                confirm_label="Widerrufen"
                on_click={JS.push("revoke_api_token", value: %{id: api_token.id})}
              />
            </.list_row>
          </.list>
          <.alert
            :if={@new_api_token}
            id="new-api-token"
            tone={:success}
            title="Neues Token, wird nur jetzt angezeigt"
            class="mt-4"
          >
            <code class="select-all wrap-anywhere">{@new_api_token}</code>
          </.alert>
          <.form for={@api_token_form} id="api-token-form" class="mt-4" phx-submit="create_api_token">
            <.input
              field={@api_token_form[:name]}
              label="Name des neuen Tokens"
              placeholder="Name, z. B. Zipfelkasse"
              maxlength="60"
              inline
              required
            >
              <.button
                type="submit"
                icon="plus"
                class="join-item"
                phx-disable-with="Wird erstellt …"
              >
                Token erstellen
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

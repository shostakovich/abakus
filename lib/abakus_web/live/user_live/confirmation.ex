defmodule AbakusWeb.UserLive.Confirmation do
  @moduledoc "The page behind a magic link: a button, so mail scanners do not use up the link."
  use AbakusWeb, :live_view

  alias Abakus.Users

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <.card title="Anmelden">
        <p class="text-body-secondary">{@user.email}</p>
        <.form
          for={@form}
          id="login-form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.button class="w-100" phx-disable-with="Anmelden …">Anmelden</.button>
        </.form>
      </.card>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Users.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, page_title: "Anmelden", user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Der Link ist ungültig oder abgelaufen.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end

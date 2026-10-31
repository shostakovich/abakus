defmodule AbakusWeb.OAuthHTML do
  @moduledoc "The page on which the budget owner confirms an app's sign-in."
  use AbakusWeb, :html

  def authorize(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <.card title="App anmelden">
        <p id="authorize-request">
          „{@request.device_name}“ möchte sich als {@request.client.name} bei Abakus anmelden.
        </p>
        <p :if={@owner?} class="text-sm text-base-content/70">
          Die App kann dann dein Budget lesen und ändern, bis du sie unter Einstellungen → Geräte abmeldest.
        </p>
        <p :if={!@owner?} id="authorize-not-owner" class="text-sm text-base-content/70">
          Nur wer das Budget führt, kann eine App anmelden.
        </p>

        <.form for={%{}} id="authorize-form" action={~p"/oauth/authorize"} class="mt-2 flex gap-2">
          <input type="hidden" name="response_type" value="code" />
          <input type="hidden" name="client_id" value={@request.client.id} />
          <input type="hidden" name="redirect_uri" value={@request.client.redirect_uri} />
          <input type="hidden" name="code_challenge" value={@request.code_challenge} />
          <input type="hidden" name="code_challenge_method" value="S256" />
          <input type="hidden" name="device_name" value={@request.device_name} />
          <input :if={@request.state} type="hidden" name="state" value={@request.state} />
          <.button
            :if={@owner?}
            id="authorize-allow"
            type="submit"
            name="decision"
            value="allow"
            variant={:primary}
            class="grow"
          >
            Anmelden
          </.button>
          <.button id="authorize-deny" type="submit" name="decision" value="deny" class="grow">
            Abbrechen
          </.button>
        </.form>
      </.card>
    </Layouts.auth>
    """
  end

  def invalid_client(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <.card title="App anmelden">
        <p id="authorize-invalid">Diese App ist bei Abakus nicht bekannt.</p>
      </.card>
    </Layouts.auth>
    """
  end
end

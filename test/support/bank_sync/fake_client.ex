defmodule Abakus.BankSync.FakeClient do
  @moduledoc """
  Enable Banking in tests, once `serve/1` started it; before that it is not configured. Its banks are Musterbank
  (consents of up to 180 days) and Sparkasse Musterstadt (90) in Germany and Banque Exemple in France; the code
  "code-1" opens `session/0`, any other code is refused with 400. It records the consents started.
  """
  @behaviour Abakus.BankSync.Client

  @day 24 * 60 * 60

  @banks [
    %{name: "Sparkasse Musterstadt", country: "DE", maximum_consent_validity: 90 * @day},
    %{name: "Musterbank", country: "DE", maximum_consent_validity: 180 * @day},
    %{name: "Banque Exemple", country: "FR", maximum_consent_validity: 180 * @day}
  ]

  @doc "Starts the fake for the test; `sessions:` replaces the sessions by code."
  def serve(opts \\ []) do
    state = %{sessions: Keyword.get(opts, :sessions, %{"code-1" => session()}), auth_requests: []}

    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start: {Agent, :start_link, [fn -> state end, [name: __MODULE__]]}
    })
  end

  @doc "A session with two accounts, a current account and a savings account, its consent until 18.04.2027."
  def session do
    %{
      session_id: "session-1",
      valid_until: ~U[2027-04-18 10:00:00.000000Z],
      accounts: [
        %{uid: "uid-giro", name: "Girokonto", iban: "DE02100200300000004711"},
        %{uid: "uid-savings", name: "Tagesgeld", iban: "DE02100200300000004712"}
      ]
    }
  end

  @doc "Makes `code` open `session`."
  def put_session(code, session),
    do: Agent.update(__MODULE__, &put_in(&1.sessions[code], session))

  @doc "The consents started, oldest first."
  def auth_requests, do: Agent.get(__MODULE__, & &1.auth_requests)

  @impl true
  def available?, do: Process.whereis(__MODULE__) != nil

  @impl true
  def banks(country) do
    if available?(),
      do: {:ok, Enum.filter(@banks, &(&1.country == country))},
      else: {:error, :not_configured}
  end

  @impl true
  def start_auth(request) do
    Agent.update(__MODULE__, &%{&1 | auth_requests: &1.auth_requests ++ [request]})
    {:ok, "https://enablebanking.example/auth/#{request.state}"}
  end

  @impl true
  def create_session(code) do
    case Agent.get(__MODULE__, & &1.sessions[code]) do
      nil -> {:error, {:http_status, 400}}
      session -> {:ok, session}
    end
  end
end

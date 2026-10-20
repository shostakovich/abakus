defmodule Abakus.BankSync.FakeClient do
  @moduledoc """
  Enable Banking in tests, once `serve/1` started it; before that it is not configured. Its banks are Musterbank
  (consents of up to 180 days) and Sparkasse Musterstadt (90) in Germany and Banque Exemple in France; the code
  "code-1" opens `session/0`, any other code is refused with 400. It records the consents started.

  Each bank account has the transactions and balances put for it, none before; it records each fetch with the PSU
  data it came with. `fail_fetches/1` makes every fetch fail.
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
    state = %{
      sessions: Keyword.get(opts, :sessions, %{"code-1" => session()}),
      auth_requests: [],
      transactions: %{},
      balances: %{},
      fetches: [],
      fetch_error: nil
    }

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

  @doc """
  Makes the bank account `uid` report `transactions` (see `transaction/1`) from the date asked for, or what a
  function of no arguments returns, as it is, when it is called (it may also raise or wait).
  """
  def put_transactions(uid, transactions),
    do: Agent.update(__MODULE__, &put_in(&1.transactions[uid], transactions))

  @doc "Makes the bank account `uid` report `balances`."
  def put_balances(uid, balances),
    do: Agent.update(__MODULE__, &put_in(&1.balances[uid], balances))

  @doc "Makes every fetch fail with `reason`; nil lets them succeed again."
  def fail_fetches(reason), do: Agent.update(__MODULE__, &%{&1 | fetch_error: reason})

  @doc "The fetches, oldest first: `{:transactions, uid, date_from, psu}` and `{:balances, uid, psu}`."
  def fetches, do: Agent.get(__MODULE__, & &1.fetches)

  @doc "A booked transaction as the client reports it, with `attrs` replacing its defaults."
  def transaction(attrs) do
    Map.merge(
      %{
        status: :booked,
        entry_reference: nil,
        transaction_id: nil,
        date: nil,
        amount: nil,
        creditor: nil,
        debtor: nil,
        remittance: []
      },
      Map.new(attrs)
    )
  end

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

  @impl true
  def transactions(uid, date_from, psu) do
    fetch({:transactions, uid, date_from, psu}, fn state ->
      case Map.get(state.transactions, uid, []) do
        report when is_function(report, 0) ->
          report

        transactions ->
          Enum.filter(transactions, &(&1.date == nil or Date.compare(&1.date, date_from) != :lt))
      end
    end)
    |> case do
      {:ok, report} when is_function(report, 0) -> {:ok, report.()}
      result -> result
    end
  end

  @impl true
  def balances(uid, psu),
    do: fetch({:balances, uid, psu}, &Map.get(&1.balances, uid, []))

  defp fetch(record, answer) do
    Agent.get_and_update(__MODULE__, fn state ->
      result = if state.fetch_error, do: {:error, state.fetch_error}, else: {:ok, answer.(state)}
      {result, %{state | fetches: state.fetches ++ [record]}}
    end)
  end
end

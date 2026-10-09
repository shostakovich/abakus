defmodule Abakus.WebAuthn.Challenges do
  @moduledoc """
  The challenges of passkey ceremonies. Each is valid for the ceremony timeout.

  Sign-in challenges are stateless: `issue_login/1` returns `{challenge, issued_at}` for the
  signed session, so anonymous requests store nothing on the server. `redeem_login/3` records
  the hash of a challenge that signed someone in until it expires and refuses one already
  recorded, so a captured cookie and assertion cannot sign in twice; failed attempts record
  nothing.

  Registration challenges (signed-in users only) stay on the server under a random id that the
  session holds, in a table with a cap: a full table is swept, and if it is still full, no
  challenge is issued. A registration challenge is taken out on its first use, whether the
  ceremony succeeds or not.

  Callers read and write the public tables directly; the process only owns them and sweeps them
  periodically.

  Options: `:name`, `:clock` (a function returning milliseconds; system time by default, as
  sign-in challenges outlive restarts in the cookie), `:ttl_ms`, `:registration_cap` and
  `:sweep_interval` in milliseconds.
  """
  use GenServer

  alias Abakus.WebAuthn

  @default_registration_cap 1_000

  @type login :: {challenge :: binary, issued_at :: integer}

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc "A new sign-in challenge for the session; stores nothing."
  @spec issue_login(atom) :: login
  def issue_login(store \\ __MODULE__), do: {WebAuthn.new_challenge(), config(store).clock.()}

  @doc """
  Runs `verify` with the challenge of `login` if it is still valid and has not signed anyone in.
  Records it once `verify` returns `{:ok, _}`; whoever records it first wins.
  """
  @spec redeem_login(atom, term, (binary -> {:ok, term} | {:error, term})) ::
          {:ok, term} | {:error, term}
  def redeem_login(store \\ __MODULE__, login, verify)

  def redeem_login(store, {challenge, issued_at}, verify)
      when is_binary(challenge) and is_integer(issued_at) do
    config = config(store)
    expires_at = issued_at + config.ttl_ms
    hash = :crypto.hash(:sha256, challenge)

    cond do
      expires_at <= config.clock.() ->
        {:error, :expired}

      :ets.member(config.spent, hash) ->
        {:error, :spent}

      true ->
        challenge |> verify.() |> record(config.spent, {hash, expires_at})
    end
  end

  def redeem_login(_store, _login, _verify), do: {:error, :missing}

  defp record({:ok, _result} = ok, spent, row),
    do: if(:ets.insert_new(spent, row), do: ok, else: {:error, :spent})

  defp record(error, _spent, _row), do: error

  @doc "Stores a new registration challenge for the user; `{:error, :busy}` while the table is full."
  @spec issue_registration(atom, term) ::
          {:ok, {id :: String.t(), challenge :: binary}} | {:error, :busy}
  def issue_registration(store \\ __MODULE__, user_id) do
    config = config(store)
    table = config.registrations

    if room?(table, config.registration_cap) or
         room_after_sweep?(table, config.registration_cap, config.clock.()) do
      id = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
      challenge = WebAuthn.new_challenge()
      :ets.insert(table, {id, user_id, challenge, config.clock.() + config.ttl_ms})
      {:ok, {id, challenge}}
    else
      {:error, :busy}
    end
  end

  @doc "Takes out the user's registration challenge stored under `id`; `nil` if there is none."
  def take_registration(store \\ __MODULE__, id, user_id)

  def take_registration(store, id, user_id) when is_binary(id) do
    config = config(store)

    case :ets.take(config.registrations, id) do
      [{^id, ^user_id, challenge, expires_at}] -> if expires_at > config.clock.(), do: challenge
      _ -> nil
    end
  end

  def take_registration(_store, _id, _user_id), do: nil

  @doc "How many rows the store holds: open registrations and spent sign-in challenges."
  def size(store \\ __MODULE__), do: store |> tables() |> Enum.sum_by(&:ets.info(&1, :size))

  @doc "Drops expired rows now; returns how many are left."
  def sweep(store \\ __MODULE__) do
    config = config(store)
    now = config.clock.()
    sweep_table(config.registrations, now)
    :ets.select_delete(config.spent, [{{:_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    size(store)
  end

  @doc "Drops all rows, e.g. between tests."
  def reset(store \\ __MODULE__), do: Enum.each(tables(store), &:ets.delete_all_objects/1)

  defp config(store), do: :persistent_term.get({__MODULE__, store})
  defp tables(store), do: [config(store).registrations, config(store).spent]

  defp room?(table, cap), do: :ets.info(table, :size) < cap

  defp room_after_sweep?(table, cap, now) do
    sweep_table(table, now)
    room?(table, cap)
  end

  defp sweep_table(table, now) do
    :ets.select_delete(table, [{{:_, :_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    table_options = [:set, :public, read_concurrency: true, write_concurrency: true]

    config = %{
      registrations: :ets.new(__MODULE__, table_options),
      spent: :ets.new(__MODULE__, table_options),
      clock: Keyword.get(opts, :clock, fn -> System.system_time(:millisecond) end),
      ttl_ms: Keyword.get(opts, :ttl_ms, WebAuthn.timeout_ms()),
      registration_cap: Keyword.get(opts, :registration_cap, @default_registration_cap)
    }

    :persistent_term.put({__MODULE__, opts[:name]}, config)
    state = %{name: opts[:name], sweep_interval: Keyword.get(opts, :sweep_interval, 60_000)}
    schedule_sweep(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep(state.name)
    schedule_sweep(state)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state), do: :persistent_term.erase({__MODULE__, state.name})

  defp schedule_sweep(state), do: Process.send_after(self(), :sweep, state.sweep_interval)
end

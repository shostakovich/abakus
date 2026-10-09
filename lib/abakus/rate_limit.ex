defmodule Abakus.RateLimit do
  @moduledoc """
  Sliding-window limits in ETS. A rule `{key, limit, window_ms}` allows `limit` hits within any
  `window_ms`. Hits go through the server, so checking several rules and counting the hit is
  atomic. Each row holds the expiry times of its hits; a periodic sweep drops expired rows.

  Options: `:name`, `:clock` (a function returning milliseconds, monotonic by default) and
  `:sweep_interval` in milliseconds.
  """
  use GenServer

  @type rule :: {key :: term, limit :: pos_integer, window_ms :: pos_integer}

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Counts a hit under every rule if all of them have room. Otherwise counts nothing and returns
  the key of the first full rule.
  """
  @spec hit(GenServer.server(), [rule]) :: :ok | {:error, key :: term}
  def hit(server \\ __MODULE__, rules), do: GenServer.call(server, {:hit, rules})

  @doc "Drops expired rows now; returns how many rows are left."
  def sweep(server \\ __MODULE__), do: GenServer.call(server, :sweep)

  def reset(server \\ __MODULE__), do: GenServer.call(server, :reset)

  @impl true
  def init(opts) do
    state = %{
      table: :ets.new(__MODULE__, [:set, :protected]),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      sweep_interval: Keyword.get(opts, :sweep_interval, 60_000)
    }

    schedule_sweep(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:hit, rules}, _from, state) do
    now = state.clock.()

    current =
      Enum.map(rules, fn {key, limit, window} -> {key, limit, window, live(state, key, now)} end)

    case Enum.find(current, fn {_key, limit, _window, expiries} -> length(expiries) >= limit end) do
      nil ->
        for {key, _limit, window, expiries} <- current do
          :ets.insert(state.table, {key, now + window, [now + window | expiries]})
        end

        {:reply, :ok, state}

      {key, _limit, _window, _expiries} ->
        {:reply, {:error, key}, state}
    end
  end

  def handle_call(:sweep, _from, state), do: {:reply, sweep_table(state), state}

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(state.table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep_table(state)
    schedule_sweep(state)
    {:noreply, state}
  end

  defp live(state, key, now) do
    case :ets.lookup(state.table, key) do
      [{^key, _last, expiries}] -> Enum.filter(expiries, &(&1 > now))
      [] -> []
    end
  end

  # A row expires with its newest hit, which is stored next to the key.
  defp sweep_table(state) do
    now = state.clock.()
    :ets.select_delete(state.table, [{{:_, :"$1", :_}, [{:"=<", :"$1", now}], [true]}])
    :ets.info(state.table, :size)
  end

  defp schedule_sweep(state), do: Process.send_after(self(), :sweep, state.sweep_interval)
end

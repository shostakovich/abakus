defmodule Abakus.RateLimitTest do
  use ExUnit.Case, async: true

  alias Abakus.RateLimit

  setup do
    clock = start_supervised!({Agent, fn -> 1_000_000 end})

    server =
      start_supervised!(
        {RateLimit, name: nil, clock: fn -> Agent.get(clock, & &1) end, sweep_interval: 3_600_000}
      )

    %{server: server, advance: fn ms -> Agent.update(clock, &(&1 + ms)) end}
  end

  test "allows `limit` hits per window and key", %{server: server} do
    rule = {:a, 2, 1_000}

    assert RateLimit.hit(server, [rule]) == :ok
    assert RateLimit.hit(server, [rule]) == :ok
    assert RateLimit.hit(server, [rule]) == {:error, :a}
    assert RateLimit.hit(server, [{:b, 2, 1_000}]) == :ok
  end

  test "the window slides: each hit expires on its own", %{server: server, advance: advance} do
    rule = {:a, 2, 1_000}

    assert RateLimit.hit(server, [rule]) == :ok
    advance.(600)
    assert RateLimit.hit(server, [rule]) == :ok
    advance.(399)
    assert RateLimit.hit(server, [rule]) == {:error, :a}

    # The first hit is 1000 ms old now, the second one still counts.
    advance.(1)
    assert RateLimit.hit(server, [rule]) == :ok
    assert RateLimit.hit(server, [rule]) == {:error, :a}

    advance.(1_000)
    assert RateLimit.hit(server, [rule]) == :ok
  end

  test "counts a hit under all rules or none", %{server: server} do
    per_key = fn key -> {{:email, key}, 3, 1_000} end
    total = {:total, 4, 10_000}

    for _ <- 1..3, do: assert(RateLimit.hit(server, [per_key.("x"), total]) == :ok)
    assert RateLimit.hit(server, [per_key.("x"), total]) == {:error, {:email, "x"}}

    # The refused hit did not use up the total.
    assert RateLimit.hit(server, [per_key.("y"), total]) == :ok
    assert RateLimit.hit(server, [per_key.("z"), total]) == {:error, :total}
    assert RateLimit.hit(server, [per_key.("z")]) == :ok
  end

  test "the sweep drops rows whose hits have all expired", %{server: server, advance: advance} do
    :ok = RateLimit.hit(server, [{:short, 5, 1_000}, {:long, 5, 5_000}])
    advance.(500)
    :ok = RateLimit.hit(server, [{:short, 5, 1_000}])

    assert RateLimit.sweep(server) == 2
    advance.(999)
    assert RateLimit.sweep(server) == 2
    advance.(1)
    assert RateLimit.sweep(server) == 1
    advance.(3_500)
    assert RateLimit.sweep(server) == 0
  end

  test "sweeps on its own" do
    server = start_supervised!({RateLimit, name: nil, sweep_interval: 10}, id: :fast)
    :ok = RateLimit.hit(server, [{:a, 1, 20}])

    Process.sleep(60)
    assert :sys.get_state(server).table |> :ets.info(:size) == 0
  end

  test "reset forgets every hit", %{server: server} do
    :ok = RateLimit.hit(server, [{:a, 1, 1_000}])
    :ok = RateLimit.reset(server)
    assert RateLimit.hit(server, [{:a, 1, 1_000}]) == :ok
  end
end

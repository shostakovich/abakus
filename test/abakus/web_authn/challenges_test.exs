defmodule Abakus.WebAuthn.ChallengesTest do
  use ExUnit.Case, async: true

  alias Abakus.WebAuthn.Challenges

  defp start(opts) do
    name = :"challenges_#{System.unique_integer([:positive])}"
    start_supervised!({Challenges, Keyword.put(opts, :name, name)}, id: name)
    name
  end

  setup do
    clock = start_supervised!({Agent, fn -> 0 end})

    store =
      start(
        clock: fn -> Agent.get(clock, & &1) end,
        ttl_ms: 1_000,
        registration_cap: 1,
        sweep_interval: 3_600_000
      )

    %{store: store, advance: fn ms -> Agent.update(clock, &(&1 + ms)) end}
  end

  defp accept(challenge), do: {:ok, challenge}

  describe "sign-in" do
    test "issues a fresh challenge every time and stores nothing", %{store: store} do
      {challenge, 0} = Challenges.issue_login(store)
      {other, 0} = Challenges.issue_login(store)

      assert byte_size(challenge) == 32
      refute challenge == other
      assert Challenges.size(store) == 0
    end

    test "a challenge signs in once", %{store: store} do
      {challenge, _} = login = Challenges.issue_login(store)

      assert Challenges.redeem_login(store, login, &accept/1) == {:ok, challenge}
      assert Challenges.size(store) == 1
      assert Challenges.redeem_login(store, login, &accept/1) == {:error, :spent}
    end

    test "a failed attempt records nothing", %{store: store} do
      {challenge, _} = login = Challenges.issue_login(store)

      assert Challenges.redeem_login(store, login, fn _ -> {:error, :signature} end) ==
               {:error, :signature}

      assert Challenges.size(store) == 0
      assert Challenges.redeem_login(store, login, &accept/1) == {:ok, challenge}
    end

    test "only one of two simultaneous sign-ins with a challenge wins", %{store: store} do
      login = Challenges.issue_login(store)
      parent = self()

      slow = fn challenge ->
        send(parent, :verified)
        assert_receive :go
        {:ok, challenge}
      end

      task = Task.async(fn -> Challenges.redeem_login(store, login, slow) end)
      assert_receive :verified
      assert {:ok, _} = Challenges.redeem_login(store, login, &accept/1)
      send(task.pid, :go)

      assert Task.await(task) == {:error, :spent}
    end

    test "a challenge expires after the ceremony timeout", %{store: store, advance: advance} do
      {challenge, _} = fresh = Challenges.issue_login(store)
      expired = Challenges.issue_login(store)

      advance.(999)
      assert Challenges.redeem_login(store, fresh, &accept/1) == {:ok, challenge}

      advance.(1)

      assert Challenges.redeem_login(store, expired, fn _ -> flunk("verified") end) ==
               {:error, :expired}
    end

    test "a missing or malformed session value gives no challenge", %{store: store} do
      for login <- [nil, "id", {"challenge", "0"}, {nil, 0}] do
        assert Challenges.redeem_login(store, login, &accept/1) == {:error, :missing}
      end
    end

    test "the sweep drops spent challenges once they expire", %{store: store, advance: advance} do
      login = Challenges.issue_login(store)
      Challenges.redeem_login(store, login, &accept/1)

      advance.(999)
      assert Challenges.sweep(store) == 1
      advance.(1)
      assert Challenges.sweep(store) == 0
    end
  end

  describe "registration" do
    test "hands out each challenge once, to its user", %{store: store} do
      {:ok, {id, challenge}} = Challenges.issue_registration(store, 1)

      assert byte_size(challenge) == 32
      assert Challenges.take_registration(store, id, 1) == challenge
      assert Challenges.take_registration(store, id, 1) == nil

      {:ok, {id, _challenge}} = Challenges.issue_registration(store, 1)
      assert Challenges.take_registration(store, id, 2) == nil
      assert Challenges.take_registration(store, id, 1) == nil
    end

    test "a challenge expires after the ceremony timeout", %{store: store, advance: advance} do
      {:ok, {id, _challenge}} = Challenges.issue_registration(store, 1)

      advance.(1_000)
      assert Challenges.take_registration(store, id, 1) == nil
    end

    test "unknown or missing ids give no challenge", %{store: store} do
      assert Challenges.take_registration(store, "unknown", 1) == nil
      assert Challenges.take_registration(store, nil, 1) == nil
      assert Challenges.take_registration(store, ["list"], 1) == nil
    end

    test "the table has a cap; a full table sweeps before it says busy", %{
      store: store,
      advance: advance
    } do
      assert {:ok, _} = Challenges.issue_registration(store, 1)
      assert Challenges.issue_registration(store, 2) == {:error, :busy}

      advance.(1_000)
      assert {:ok, _} = Challenges.issue_registration(store, 2)
      assert Challenges.size(store) == 1
    end
  end

  test "issuing and redeeming do not wait for the owner", %{store: store} do
    :sys.suspend(Process.whereis(store))
    {:ok, {id, challenge}} = Challenges.issue_registration(store, 1)
    assert Challenges.take_registration(store, id, 1) == challenge
    assert {:ok, _} = Challenges.redeem_login(store, Challenges.issue_login(store), &accept/1)
    :sys.resume(Process.whereis(store))
  end

  test "sweeps on its own" do
    store = start(ttl_ms: 20, sweep_interval: 10)
    Challenges.issue_registration(store, 1)
    assert Challenges.size(store) == 1

    assert Enum.any?(1..50, fn _ ->
             Process.sleep(10)
             Challenges.size(store) == 0
           end)
  end
end

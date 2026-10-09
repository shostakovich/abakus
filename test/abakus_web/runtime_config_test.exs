defmodule AbakusWeb.RuntimeConfigTest do
  # Sets environment variables, so it cannot run alongside other tests.
  use ExUnit.Case, async: false

  @env %{
    "PHX_HOST" => "abakus.example.org",
    "DATABASE_PATH" => "/tmp/abakus-runtime-config-test.sqlite3",
    "SECRET_KEY_BASE" => String.duplicate("a", 64)
  }

  setup do
    previous = Map.new(@env, fn {name, _} -> {name, System.get_env(name)} end)
    System.put_env(@env)

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  test "production accepts LiveView sockets only from the public HTTPS origin" do
    config = Config.Reader.read!("config/runtime.exs", env: :prod)
    endpoint = config[:abakus][AbakusWeb.Endpoint]

    assert endpoint[:check_origin] == ["https://abakus.example.org"]
  end

  test "the port from PORT applies only in development and production" do
    assert Application.fetch_env!(:abakus, AbakusWeb.Endpoint)[:http][:port] == 4002
    refute Config.Reader.read!("config/runtime.exs", env: :test)[:abakus][AbakusWeb.Endpoint]
  end

  test "production refuses to start without a public host" do
    System.delete_env("PHX_HOST")

    assert_raise RuntimeError, ~r/PHX_HOST is missing/, fn ->
      Config.Reader.read!("config/runtime.exs", env: :prod)
    end
  end
end

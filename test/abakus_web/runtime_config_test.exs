defmodule AbakusWeb.RuntimeConfigTest do
  # Sets environment variables, so it cannot run alongside other tests.
  use ExUnit.Case, async: false

  @env %{
    "PHX_HOST" => "abakus.example.org",
    "DATABASE_PATH" => "/tmp/abakus-runtime-config-test.sqlite3",
    "SECRET_KEY_BASE" => String.duplicate("a", 64),
    "SMTP_HOST" => "smtp.example.org",
    "SMTP_PORT" => "465",
    "SMTP_USERNAME" => "abakus@example.org",
    "SMTP_PASSWORD" => "secret",
    "MAIL_FROM" => "abakus@example.org"
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

  test "production mails over verified TLS and accepts wildcard certificates" do
    config = Config.Reader.read!("config/runtime.exs", env: :prod)
    mailer = config[:abakus][Abakus.Mailer]

    assert mailer[:adapter] == Swoosh.Adapters.SMTP
    assert mailer[:relay] == "smtp.example.org"
    assert mailer[:ssl] and mailer[:tls] == :never
    assert mailer[:sockopts][:verify] == :verify_peer
    assert mailer[:sockopts][:server_name_indication] == ~c"smtp.example.org"
    assert [match_fun: match_fun] = mailer[:sockopts][:customize_hostname_check]
    assert is_function(match_fun, 2)
    assert config[:abakus][:mail_from] == {"Abakus", "abakus@example.org"}
  end

  test "production refuses to start without a public host" do
    System.delete_env("PHX_HOST")

    assert_raise RuntimeError, ~r/PHX_HOST is missing/, fn ->
      Config.Reader.read!("config/runtime.exs", env: :prod)
    end
  end
end

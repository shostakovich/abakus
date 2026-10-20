defmodule AbakusWeb.RuntimeConfigTest do
  # Sets environment variables, so it cannot run alongside other tests.
  use ExUnit.Case, async: false

  alias Abakus.Network

  @mcp ~w(MCP_SECRET MCP_ALLOWED_CIDRS TRUSTED_PROXIES ENABLE_BANKING_APP_ID ENABLE_BANKING_KEY_FILE)
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
    previous = Map.new(Map.keys(@env) ++ @mcp, &{&1, System.get_env(&1)})
    Enum.each(@mcp, &System.delete_env/1)
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

  defp mcp(env \\ :prod), do: Config.Reader.read!("config/runtime.exs", env: env)[:abakus][:mcp]

  defp networks(text) do
    {:ok, networks} = Network.parse_list(text)
    networks
  end

  test "MCP is off and allows Anthropic's range by default, behind no trusted proxy" do
    assert mcp() == [secret: nil, allowed_cidrs: networks("160.79.104.0/21"), trusted_proxies: []]
  end

  test "MCP reads its variables trimmed, an empty value counting as unset" do
    System.put_env(%{
      "MCP_SECRET" => " s3cret ",
      "MCP_ALLOWED_CIDRS" => "10.0.0.0/8, 192.168.1.5",
      "TRUSTED_PROXIES" => "172.18.0.2 fd00::/8"
    })

    assert mcp() == [
             secret: "s3cret",
             allowed_cidrs: networks("10.0.0.0/8 192.168.1.5"),
             trusted_proxies: networks("172.18.0.2, fd00::/8")
           ]

    System.put_env(%{"MCP_SECRET" => " ", "MCP_ALLOWED_CIDRS" => ""})
    assert mcp()[:secret] == nil
    assert mcp()[:allowed_cidrs] == networks("160.79.104.0/21")
  end

  for {name, value, message} <- [
        {"MCP_ALLOWED_CIDRS", "10.0.0.0/33",
         ~s(invalid MCP_ALLOWED_CIDRS: "33" is not a valid prefix length for 10.0.0.0)},
        {"TRUSTED_PROXIES", "10.0.0.1 garbage",
         ~s(invalid TRUSTED_PROXIES: "garbage" is not an IP address or network)}
      ] do
    test "refuses #{name}=#{value}, naming the variable" do
      System.put_env(unquote(name), unquote(value))
      assert_raise RuntimeError, unquote(message), fn -> mcp() end
    end
  end

  test "tests ignore the MCP variables" do
    System.put_env(%{"MCP_SECRET" => "s3cret", "MCP_ALLOWED_CIDRS" => "garbage"})
    assert mcp(:test)[:secret] == nil
  end

  defp enable_banking(env \\ :prod),
    do:
      Config.Reader.read!("config/runtime.exs", env: env)[:abakus][Abakus.BankSync.EnableBanking]

  test "bank sync reads the application id and the key file trimmed, an empty value counting as unset" do
    assert enable_banking() == [app_id: nil, key_file: nil]

    System.put_env(%{
      "ENABLE_BANKING_APP_ID" => " app-1 ",
      "ENABLE_BANKING_KEY_FILE" => "/run/secrets/enable-banking.pem"
    })

    assert enable_banking() == [app_id: "app-1", key_file: "/run/secrets/enable-banking.pem"]
    assert enable_banking(:test) == [app_id: nil, key_file: nil]

    System.put_env("ENABLE_BANKING_APP_ID", "")
    assert enable_banking()[:app_id] == nil
  end
end

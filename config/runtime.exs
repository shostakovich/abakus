import Config

if System.get_env("PHX_SERVER") do
  config :abakus, AbakusWeb.Endpoint, server: true
end

# Trimmed; an empty value counts as unset. Tests configure the MCP and bank sync themselves.
optional_env = fn name ->
  value = if config_env() != :test, do: name |> System.get_env("") |> String.trim(), else: ""
  if value != "", do: value
end

networks! = fn name, default ->
  case Abakus.Network.parse_list(optional_env.(name) || default) do
    {:ok, networks} -> networks
    {:error, reason} -> raise "invalid #{name}: #{reason}"
  end
end

config :abakus, :mcp,
  secret: optional_env.("MCP_SECRET"),
  allowed_cidrs: networks!.("MCP_ALLOWED_CIDRS", "160.79.104.0/21"),
  trusted_proxies: networks!.("TRUSTED_PROXIES", "")

# Countries, sectors and dividends of the Depot's securities; without a key DivvyDiary is never asked.
config :abakus, Abakus.Depot.MarketData.DivvyDiary, api_key: System.get_env("DIVVYDIARY_API_KEY")

# The Depot's receipt recognition by any OpenAI-compatible chat API, e.g. http://ollama:11434/v1; without URL and
# model, receipts still land in the inbox and open an empty form.
config :abakus, Abakus.Depot.Receipts.ChatAPI,
  url: System.get_env("RECEIPT_MODEL_URL"),
  model: System.get_env("RECEIPT_MODEL"),
  api_key: System.get_env("RECEIPT_MODEL_KEY"),
  thinking: System.get_env("RECEIPT_MODEL_THINKING") in ~w(on true 1)

# Bank sync through Enable Banking: the application's id and the path of its private key, mounted read only;
# without both the tab Bankverbindungen says bank sync is not set up.
config :abakus, Abakus.BankSync.EnableBanking,
  app_id: optional_env.("ENABLE_BANKING_APP_ID"),
  key_file: optional_env.("ENABLE_BANKING_KEY_FILE")

port = String.to_integer(System.get_env("PORT", "4000"))

if config_env() == :dev do
  config :abakus, AbakusWeb.Endpoint, http: [port: port], url: [port: port]
end

if config_env() == :prod do
  env! = fn name, example ->
    System.get_env(name) || raise "environment variable #{name} is missing, e.g. #{example}"
  end

  database = env!.("DATABASE_PATH", "/app/data/abakus.sqlite3")

  config :abakus, Abakus.Repo,
    database: database,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))

  config :abakus, :backup_dir, Path.join(Path.dirname(database), "backups")

  host = env!.("PHX_HOST", "abakus.example.org")

  # The browser's Origin header names the public https URL even behind the proxy, so the
  # scheme is compared as well.
  config :abakus, AbakusWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    check_origin: ["https://" <> host],
    secret_key_base: env!.("SECRET_KEY_BASE", "the output of `openssl rand -hex 64`")

  smtp_host = env!.("SMTP_HOST", "smtp.example.com")
  smtp_port = String.to_integer(System.get_env("SMTP_PORT", "587"))

  verify_tls = [
    verify: :verify_peer,
    cacerts: :public_key.cacerts_get(),
    server_name_indication: String.to_charlist(smtp_host),
    depth: 99,
    # Providers with wildcard certificates fail OTP's default hostname check.
    customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
  ]

  # Port 465 speaks TLS from the start, any other port upgrades with STARTTLS.
  config :abakus, Abakus.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: smtp_port,
    username: env!.("SMTP_USERNAME", "abakus@example.com"),
    password: env!.("SMTP_PASSWORD", "secret"),
    auth: :always,
    ssl: smtp_port == 465,
    sockopts: if(smtp_port == 465, do: verify_tls, else: []),
    tls: if(smtp_port == 465, do: :never, else: :always),
    tls_options: verify_tls,
    retries: 1

  config :abakus, :mail_from, {"Abakus", env!.("MAIL_FROM", "abakus@example.com")}
end

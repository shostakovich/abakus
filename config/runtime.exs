import Config

if System.get_env("PHX_SERVER") do
  config :abakus, AbakusWeb.Endpoint, server: true
end

port = String.to_integer(System.get_env("PORT", "4000"))

if config_env() == :dev do
  config :abakus, AbakusWeb.Endpoint, http: [port: port], url: [port: port]
end

if config_env() == :prod do
  env! = fn name, example ->
    System.get_env(name) || raise "environment variable #{name} is missing, e.g. #{example}"
  end

  config :abakus, Abakus.Repo,
    database: env!.("DATABASE_PATH", "/app/data/abakus.sqlite3"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))

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

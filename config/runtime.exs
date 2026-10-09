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
end

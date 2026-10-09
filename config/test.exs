import Config

# One connection: the sandbox opens a deferred BEGIN, and a second one flakes with "database busy".
config :abakus, Abakus.Repo,
  database: Path.expand("../tmp/test#{System.get_env("MIX_TEST_PARTITION")}.sqlite3", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1

config :abakus, AbakusWeb.Endpoint,
  url: [host: "localhost", port: 4002],
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "rOf9VO7HtRU4l1h/MfY/N2mQYh3e2+QcoEsSOK3jp7q4Rieyv5yiJmpDeP915xFP",
  server: false

config :abakus, Abakus.Mailer, adapter: Swoosh.Adapters.Test

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view, enable_expensive_runtime_checks: true

config :phoenix, sort_verified_routes_query_params: true

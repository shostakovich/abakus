import Config

database = Path.expand("../tmp/test#{System.get_env("MIX_TEST_PARTITION")}.sqlite3", __DIR__)

# One connection: the sandbox opens a deferred BEGIN, and a second one flakes with "database busy".
config :abakus, Abakus.Repo,
  database: database,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1

config :abakus, :backup_dir, Path.join(Path.dirname(database), "backups")

config :abakus, jobs: false

config :abakus, :sync_wait, 100

config :abakus, Abakus.ExchangeRates, source: Abakus.FakeExchangeRateSource

config :abakus, Abakus.BankSync, client: Abakus.BankSync.FakeClient

config :abakus, Abakus.Depot.MarketData,
  price_feed: Abakus.Depot.FakePriceFeed,
  symbol_search: Abakus.Depot.FakeSymbolSearch,
  symbol_source: Abakus.Depot.FakeSymbolSource,
  probe_timeout: 200

config :abakus, Abakus.Paperless,
  client: Abakus.FakePaperless,
  poll_interval: 1,
  consume_timeout: 100

config :abakus, Abakus.Bookkeeping.Elster,
  client: Abakus.Bookkeeping.FakeElster,
  vendor_id: "74931"

config :abakus, Abakus.Bookkeeping.Lexoffice, client: Abakus.Bookkeeping.FakeLexoffice

config :abakus, Abakus.Bookkeeping.Lexoffice.API, interval: 0, retry_after: 0

config :abakus, Abakus.Depot.Receipts,
  model: Abakus.Depot.FakeModel,
  text_extractor: Abakus.Depot.FakeTextExtractor

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

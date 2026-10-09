import Config

config :abakus,
  ecto_repos: [Abakus.Repo],
  generators: [timestamp_type: :utc_datetime_usec]

config :abakus, Abakus.Repo,
  journal_mode: :wal,
  synchronous: :normal,
  foreign_keys: :on,
  busy_timeout: 15_000,
  # A deferred read-then-write fails with SQLITE_BUSY at once; immediate ones wait at BEGIN.
  default_transaction_mode: :immediate,
  pool_size: 5,
  # :serial is AUTOINCREMENT in SQLite, so ids are never reused.
  migration_primary_key: [type: :serial, null: false],
  migration_timestamps: [type: :utc_datetime_usec]

config :abakus, AbakusWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AbakusWeb.ErrorHTML, json: AbakusWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Abakus.PubSub,
  live_view: [signing_salt: "cU0R/XpG"]

config :phoenix_live_view, root_tag_attribute: "phx-r"

config :abakus, Abakus.Mailer, adapter: Swoosh.Adapters.Local
config :abakus, :mail_from, {"Abakus", "abakus@localhost"}
config :swoosh, :api_client, false
config :swoosh, :json_library, JSON

config :esbuild,
  version: "0.25.4",
  abakus: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  abakus_css: [
    args: ~w(css/app.css --bundle --outdir=../priv/static/assets/css),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, JSON
config :ecto_sqlite3, json_library: JSON

import_config "#{config_env()}.exs"

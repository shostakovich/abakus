import Config

config :abakus, AbakusWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

config :abakus, forwarded_ssl: true

config :logger, level: :info

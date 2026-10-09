defmodule AbakusWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :abakus

  @session_options [
    store: :cookie,
    key: "_abakus_key",
    signing_salt: "zFoyQv9M",
    same_site: "Lax"
  ]

  if Application.compile_env(:abakus, :forwarded_ssl, false) do
    plug AbakusWeb.ForwardedSSL
  end

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :abakus,
    gzip: not code_reloading?,
    only: AbakusWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :abakus
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint], log: {__MODULE__, :log_level, []}

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug AbakusWeb.Router

  # Health checks poll /up and would flood the log.
  def log_level(%Plug.Conn{path_info: ["up"]}), do: false
  def log_level(_conn), do: :info
end

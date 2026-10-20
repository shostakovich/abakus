defmodule AbakusWeb.Router do
  use AbakusWeb, :router

  import AbakusWeb.UserAuth
  import AbakusWeb.Areas, only: [require_area: 2, require_part: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AbakusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :fetch_current_scope_for_user
  end

  # JSON for the passkey hooks; same session and CSRF protection as the pages.
  pipeline :browser_json do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :fetch_current_scope_for_user
  end

  pipeline :budget do
    plug :require_area, :budget
  end

  pipeline :kasse do
    plug :require_area, :kasse
  end

  pipeline :depot do
    plug :require_area, :finanzen
  end

  pipeline :kasse_settings do
    plug :require_part, :kasse
  end

  # Public without a session: the health check and `/mcp/<secret>`, which checks its callers itself. Everything
  # else requires a signed-in user.
  scope "/", AbakusWeb do
    get "/up", HealthController, :show
    forward "/mcp", MCPPlug, [], log: false
  end

  scope "/", AbakusWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/", PageController, :home
    get "/settings", PageController, :settings
  end

  scope "/budget", AbakusWeb do
    pipe_through [:browser, :require_authenticated_user, :budget]

    get "/accounts", PageController, :accounts
    get "/bank-connections/authorize", BankConnectionController, :authorize
    get "/bank-connections/callback", BankConnectionController, :callback

    live_session :budget,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, {:require, :budget}},
        {AbakusWeb.AccountGroups, :assign},
        {AbakusWeb.AccountDialog, :attach},
        {AbakusWeb.Depot.Sidebar, :budget},
        {AbakusWeb.BankConsents, :assign}
      ] do
      live "/", BudgetLive
      live "/accounts/all", RegisterLive, :all
      live "/accounts/:id", RegisterLive, :show
      live "/import", ImportLive
      live "/bank-connections", BankConnectionsLive, :index
      live "/bank-connections/:id/accounts", BankConnectionsLive, :accounts
    end
  end

  scope "/kasse", AbakusWeb.Kasse do
    pipe_through [:browser, :require_authenticated_user, :kasse]

    live_session :kasse,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, {:require, :kasse}}
      ] do
      live "/", ExpensesLive
      live "/expenses/new", ExpenseLive, :new
      live "/expenses/:id", ExpenseLive, :edit
      live "/balances", BalancesLive
      live "/activity", ActivityLive
    end
  end

  scope "/depot", AbakusWeb.Depot do
    pipe_through [:browser, :require_authenticated_user, :depot]

    live_session :depot,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, {:require, :finanzen}},
        {AbakusWeb.AccountGroups, :assign},
        {AbakusWeb.AccountDialog, :attach},
        AbakusWeb.Depot.Sidebar,
        AbakusWeb.Depot.TransactionDialog,
        {AbakusWeb.BankConsents, :assign}
      ] do
      live "/", WealthLive
      live "/holdings", HoldingsLive
      live "/dividends", DividendsLive
      live "/transactions", TransactionsLive
      live "/performance", PerformanceLive
      live "/securities", SecuritiesLive
      live "/securities/:id", SecurityLive
      live "/receipts", ReceiptsLive
    end

    get "/receipts/:id", ReceiptController, :show
  end

  scope "/settings", AbakusWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :settings,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, :assign},
        AbakusWeb.SettingsNav
      ] do
      live "/appearance", SettingsLive
      live "/depot/portfolios", Depot.PortfoliosLive
      live "/depot/receipt-intake", Depot.ReceiptIntakeLive
    end
  end

  scope "/settings/kasse", AbakusWeb.Kasse do
    pipe_through [:browser, :require_authenticated_user, :kasse_settings]

    live_session :kasse_settings,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, {:assign, :kasse}},
        AbakusWeb.SettingsNav
      ] do
      live "/", SettingsLive
      live "/participants", ParticipantsLive
      live "/categories", CategoriesLive
      live "/recurring", RecurringLive
      live "/recurring/new", RecurringNewLive
      live "/rates", RatesLive
      live "/budget", BudgetLinkLive
      live "/export", ExportLive
    end

    get "/export/expenses.csv", ExportController, :expenses_csv
    get "/export/expenses.json", ExportController, :expenses_json
  end

  # A live_session of its own, so every visit goes through the plug and can return here.
  scope "/", AbakusWeb do
    pipe_through [:browser, :require_authenticated_user, :require_sudo_mode]

    live_session :require_sudo_mode,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, :assign},
        AbakusWeb.SettingsNav
      ] do
      live "/settings/access", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", AbakusWeb do
    pipe_through [:browser_json, :require_authenticated_user]

    post "/users/settings/passkeys/options", PasskeyController, :registration_options
    post "/users/settings/passkeys", PasskeyController, :create
  end

  scope "/", AbakusWeb do
    pipe_through :browser_json

    post "/users/passkeys/options", PasskeyController, :authentication_options
  end

  scope "/", AbakusWeb do
    pipe_through :browser

    live_session :current_user,
      on_mount: [{AbakusWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  if Application.compile_env(:abakus, :dev_routes) do
    pipeline :dev_tools do
      plug :fetch_session
      plug :protect_from_forgery
      plug :mailbox_policy
    end

    scope "/dev" do
      pipe_through :dev_tools

      forward "/mailbox", Plug.Swoosh.MailboxPreview,
        csp_nonce_assign_key: %{script: :csp_nonce, style: :csp_nonce}
    end

    # The mailbox preview frames HTML mails, which bring their own styles.
    defp mailbox_policy(conn, _opts) do
      put_resp_header(
        conn,
        "content-security-policy",
        "default-src 'self'; script-src 'self' 'nonce-#{conn.assigns.csp_nonce}'; " <>
          "style-src 'self' 'unsafe-inline'; img-src 'self' data:; object-src 'none'; " <>
          "frame-ancestors 'self'; base-uri 'self'; form-action 'self'"
      )
    end
  end
end

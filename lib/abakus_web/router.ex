defmodule AbakusWeb.Router do
  use AbakusWeb, :router

  import AbakusWeb.UserAuth
  import AbakusWeb.Areas, only: [require_area: 2]

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

  # Public without a session: the health check here and later `/mcp/<secret>` with its own pipeline. Everything
  # else requires a signed-in user.
  scope "/", AbakusWeb do
    get "/up", HealthController, :show
  end

  scope "/", AbakusWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/", PageController, :home
  end

  scope "/budget", AbakusWeb do
    pipe_through [:browser, :require_authenticated_user, :budget]

    live_session :budget,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, {:require, :budget}},
        {AbakusWeb.AccountGroups, :assign},
        {AbakusWeb.AccountDialog, :attach}
      ] do
      live "/", BudgetLive
      live "/accounts", AccountsLive
      live "/accounts/all", RegisterLive, :all
      live "/accounts/:id", RegisterLive, :show
      live "/import", ImportLive
    end
  end

  scope "/kasse", AbakusWeb.Kasse do
    pipe_through [:browser, :require_authenticated_user, :kasse]

    live_session :kasse,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, {:require, :kasse}},
        {AbakusWeb.AccountGroups, :assign},
        {AbakusWeb.AccountDialog, :attach},
        AbakusWeb.Kasse.CurrentParticipant
      ] do
      live "/", ExpensesLive
      live "/expenses/new", ExpenseLive, :new
      live "/expenses/:id", ExpenseLive, :edit
      live "/balances", BalancesLive
      live "/activity", ActivityLive
      live "/settings", SettingsLive
      live "/settings/participants", ParticipantsLive
      live "/settings/categories", CategoriesLive
      live "/settings/recurring", RecurringLive
      live "/settings/recurring/new", RecurringNewLive
      live "/settings/rates", RatesLive
      live "/export", ExportLive
    end

    get "/export/expenses.csv", ExportController, :expenses_csv
    get "/export/expenses.json", ExportController, :expenses_json
  end

  scope "/", AbakusWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :settings,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, :assign},
        {AbakusWeb.AccountGroups, :assign},
        {AbakusWeb.AccountDialog, :attach}
      ] do
      live "/settings", SettingsLive, :index
      live "/settings/appearance", SettingsLive, :appearance
      live "/settings/ynab", SettingsLive, :ynab
    end
  end

  # A live_session of its own, so every visit goes through the plug and can return here.
  scope "/", AbakusWeb do
    pipe_through [:browser, :require_authenticated_user, :require_sudo_mode]

    live_session :require_sudo_mode,
      on_mount: [
        {AbakusWeb.UserAuth, :require_authenticated},
        {AbakusWeb.Areas, :assign},
        {AbakusWeb.AccountGroups, :assign},
        {AbakusWeb.AccountDialog, :attach}
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

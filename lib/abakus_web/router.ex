defmodule AbakusWeb.Router do
  use AbakusWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AbakusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", AbakusWeb do
    get "/up", HealthController, :show
  end

  scope "/", AbakusWeb do
    pipe_through :browser

    live "/", BudgetLive
  end

  if Application.compile_env(:abakus, :dev_routes) do
    pipeline :dev_tools do
      plug :fetch_session
      plug :protect_from_forgery
    end

    scope "/dev" do
      pipe_through :dev_tools

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

defmodule Abakus.Repo do
  use Ecto.Repo,
    otp_app: :abakus,
    adapter: Ecto.Adapters.SQLite3
end

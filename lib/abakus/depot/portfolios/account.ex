defmodule Abakus.Depot.Portfolios.Account do
  @moduledoc "A cash account in one currency; it exists on its own, not as part of a portfolio."
  use Abakus.Schema

  schema "depot_accounts" do
    belongs_to :user, Abakus.Users.User
    field :name, :string
    field :currency, :string
    field :note, :string
    field :retired, :boolean, default: false
    field :attributes, :map, default: %{}
    field :pp_uuid, :string

    timestamps()
  end
end

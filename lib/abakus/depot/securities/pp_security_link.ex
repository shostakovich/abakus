defmodule Abakus.Depot.Securities.PPSecurityLink do
  @moduledoc """
  Which security a user's PP file means by a PP UUID. Securities are shared, the UUIDs are per
  file, so a re-import finds its securities through these links.
  """
  use Abakus.Schema

  schema "depot_pp_security_links" do
    belongs_to :user, Abakus.Users.User
    belongs_to :security, Abakus.Depot.Securities.Security
    field :pp_uuid, :string

    timestamps()
  end
end

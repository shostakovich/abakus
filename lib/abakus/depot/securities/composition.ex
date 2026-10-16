defmodule Abakus.Depot.Securities.Composition do
  @moduledoc """
  A fund's weights per country (ISO 3166 code) and per sector, as DivvyDiary delivered them at
  `fetched_at`; one per security, which the daily job replaces.
  """
  use Abakus.Schema

  schema "depot_compositions" do
    belongs_to :security, Abakus.Depot.Securities.Security
    field :countries, :map
    field :sectors, :map
    field :fetched_at, :utc_datetime_usec
  end
end

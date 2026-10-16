defmodule Abakus.Depot.Securities.DivvyDiaryDividend do
  @moduledoc """
  A dividend as DivvyDiary delivered it at `fetched_at`, per share × 10⁸ in `currency`; the ex
  date may be nil. DivvyDiary's own forecasts are not stored.
  """
  use Abakus.Schema

  schema "depot_divvy_diary_dividends" do
    belongs_to :security, Abakus.Depot.Securities.Security
    field :ex_date, :date
    field :pay_date, :date
    field :per_share, :integer
    field :currency, :string
    field :fetched_at, :utc_datetime_usec
  end
end

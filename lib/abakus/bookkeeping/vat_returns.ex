defmodule Abakus.Bookkeeping.VatReturns do
  @moduledoc """
  The user's VAT returns (`Abakus.Bookkeeping.VatReturn`), computed from their tax lines on any of their accounts
  (`Abakus.Bookkeeping.entries/3`) and the disposals of their fixed assets, each on its own date.
  """

  alias Abakus.Bookkeeping
  alias Abakus.Bookkeeping.{FixedAssets, VatReturn}
  alias Abakus.Users.Scope

  @doc "The Voranmeldung of `quarter` (1 to 4) of `year`."
  def quarter(%Scope{} = scope, year, quarter) do
    {first, last} = VatReturn.quarter_span(year, quarter)
    VatReturn.quarter(year, quarter, entries(scope, first, last))
  end

  @doc "The Umsatzsteuererklärung of `year`."
  def year(%Scope{} = scope, year),
    do: VatReturn.year(year, entries(scope, Date.new!(year, 1, 1), Date.new!(year, 12, 31)))

  defp entries(scope, first, last),
    do:
      Bookkeeping.entries(scope, first, last) ++ FixedAssets.disposal_entries(scope, first, last)
end

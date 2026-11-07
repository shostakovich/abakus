defmodule Abakus.Bookkeeping.VatReturns do
  @moduledoc """
  The user's VAT returns (`Abakus.Bookkeeping.VatReturn`), computed from their tax lines on any of their accounts
  (`Abakus.Bookkeeping.entries/3`) and the disposals of their fixed assets, each on its own date.
  """

  alias Abakus.Bookkeeping
  alias Abakus.Bookkeeping.{Filings, FixedAssets, VatReturn}
  alias Abakus.Users.Scope

  @doc "The Voranmeldung of `quarter` (1 to 4) of `year`."
  def quarter(%Scope{} = scope, year, quarter) do
    {first, last} = VatReturn.quarter_span(year, quarter)
    VatReturn.quarter(year, quarter, entries(scope, first, last))
  end

  @doc "The Umsatzsteuererklärung of `year`, with the dues of the quarters sent from Abakus as they were sent."
  def year(%Scope{} = scope, year) do
    sent_dues =
      for quarter <- 1..4,
          filing = Filings.sent(scope, {:vat_quarter, year, quarter}),
          filing && not filing.filed_elsewhere,
          into: %{},
          do: {quarter, filing.kennzahlen["83"]}

    VatReturn.year(
      year,
      entries(scope, Date.new!(year, 1, 1), Date.new!(year, 12, 31)),
      sent_dues
    )
  end

  defp entries(scope, first, last),
    do:
      Bookkeeping.entries(scope, first, last) ++ FixedAssets.disposal_entries(scope, first, last)
end

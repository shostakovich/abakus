defmodule Abakus.Depot.Allocation.Region do
  @moduledoc """
  The fixed region blocks of the allocation: USA, Kanada, Europa, Japan, Pazifik ohne Japan and
  Schwellenländer. A country goes to its block by MSCI's market classification; every country MSCI
  does not classify as developed counts as an emerging market.
  """

  @type t :: :usa | :canada | :europe | :japan | :pacific_ex_japan | :emerging_markets

  # MSCI's 23 developed markets by MSCI region, as of the MSCI 2026 Market Classification Review
  # (msci.com, "Market Classification"). Israel is in MSCI's "Europe & Middle East"; Greece moves
  # from emerging to developed at the May 2027 index review.
  @developed %{
    "US" => :usa,
    "CA" => :canada,
    "AT" => :europe,
    "BE" => :europe,
    "CH" => :europe,
    "DE" => :europe,
    "DK" => :europe,
    "ES" => :europe,
    "FI" => :europe,
    "FR" => :europe,
    "GB" => :europe,
    "IE" => :europe,
    "IL" => :europe,
    "IT" => :europe,
    "NL" => :europe,
    "NO" => :europe,
    "PT" => :europe,
    "SE" => :europe,
    "JP" => :japan,
    "AU" => :pacific_ex_japan,
    "HK" => :pacific_ex_japan,
    "NZ" => :pacific_ex_japan,
    "SG" => :pacific_ex_japan
  }

  @doc "The block of a country given as ISO 3166 alpha-2 code."
  @spec of(String.t()) :: t
  def of(country), do: Map.get(@developed, country, :emerging_markets)
end

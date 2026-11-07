defmodule Abakus.Bookkeeping.Countries do
  @moduledoc """
  The countries a customer may be in, by ISO 3166 code with their German name: Germany, the rest of the EU, and the
  neighbours and partners beyond it that a freelancer bills.
  """

  @eu [
    {"BE", "Belgien"},
    {"BG", "Bulgarien"},
    {"DK", "Dänemark"},
    {"DE", "Deutschland"},
    {"EE", "Estland"},
    {"FI", "Finnland"},
    {"FR", "Frankreich"},
    {"GR", "Griechenland"},
    {"IE", "Irland"},
    {"IT", "Italien"},
    {"HR", "Kroatien"},
    {"LV", "Lettland"},
    {"LT", "Litauen"},
    {"LU", "Luxemburg"},
    {"MT", "Malta"},
    {"NL", "Niederlande"},
    {"AT", "Österreich"},
    {"PL", "Polen"},
    {"PT", "Portugal"},
    {"RO", "Rumänien"},
    {"SE", "Schweden"},
    {"SK", "Slowakei"},
    {"SI", "Slowenien"},
    {"ES", "Spanien"},
    {"CZ", "Tschechien"},
    {"HU", "Ungarn"},
    {"CY", "Zypern"}
  ]

  @others [
    {"AU", "Australien"},
    {"CA", "Kanada"},
    {"IS", "Island"},
    {"LI", "Liechtenstein"},
    {"NO", "Norwegen"},
    {"CH", "Schweiz"},
    {"GB", "Vereinigtes Königreich"},
    {"US", "Vereinigte Staaten"}
  ]

  @names Map.new(@eu ++ @others)

  @doc "Every code."
  def codes, do: Map.keys(@names)

  @doc "The options of a select, by German name."
  def options,
    do:
      Enum.sort_by(@eu ++ @others, &elem(&1, 1)) |> Enum.map(fn {code, name} -> {name, code} end)

  @doc "The German name of a country, its code for one not in the list, such as a customer's from Lexoffice."
  def name(code), do: Map.get(@names, code, code)

  @doc "Whether a country is in the EU but not Germany, where a business customer owes the VAT itself."
  def other_eu?(code), do: code != "DE" and List.keymember?(@eu, code, 0)
end

defmodule Abakus.Bookkeeping.States do
  @moduledoc """
  The German states a tax office is in, by their ISO 3166-2 code with their name and the Landesnummer ERiC takes to
  write a tax number in ELSTER's format: the first digits of the state's tax offices' numbers.
  """

  @states [
    {"BW", "Baden-Württemberg", "28"},
    {"BY", "Bayern", "9"},
    {"BE", "Berlin", "11"},
    {"BB", "Brandenburg", "30"},
    {"HB", "Bremen", "24"},
    {"HH", "Hamburg", "22"},
    {"HE", "Hessen", "26"},
    {"MV", "Mecklenburg-Vorpommern", "40"},
    {"NI", "Niedersachsen", "23"},
    {"NW", "Nordrhein-Westfalen", "5"},
    {"RP", "Rheinland-Pfalz", "27"},
    {"SL", "Saarland", "10"},
    {"SN", "Sachsen", "32"},
    {"ST", "Sachsen-Anhalt", "31"},
    {"SH", "Schleswig-Holstein", "21"},
    {"TH", "Thüringen", "41"}
  ]

  def codes, do: for({code, _name, _number} <- @states, do: code)

  @doc "The options of a select, by name."
  def options, do: for({code, name, _number} <- @states, do: {name, code})

  def name(code), do: Enum.find_value(@states, fn {c, name, _number} -> c == code && name end)

  @doc "The Landesnummer of the state."
  def number(code),
    do: Enum.find_value(@states, fn {c, _name, number} -> c == code && number end)
end

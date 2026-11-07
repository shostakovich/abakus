defmodule Abakus.Xml do
  @moduledoc """
  Small XML as iodata: an element with attributes and either text or children, where a child that is `nil` or
  `false` is left out. Text and attribute values are escaped, and the control characters XML 1.0 does not allow are
  taken out.
  """

  @doc "The element `name` with `attributes` (`{name, value}` pairs) around `text` or a list of children."
  def element(name, attributes \\ [], content)

  def element(name, attributes, content) when is_list(content),
    do: ["<", name, attributes(attributes), ">", Enum.filter(content, & &1), "</", name, ">"]

  def element(name, attributes, text) when is_binary(text),
    do: ["<", name, attributes(attributes), ">", escape(text), "</", name, ">"]

  defp attributes(attributes),
    do: for({key, value} <- attributes, do: [" ", key, ~s(="), escape(value), ~s(")])

  defp escape(text) do
    text
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end

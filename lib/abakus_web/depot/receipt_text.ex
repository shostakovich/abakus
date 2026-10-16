defmodule AbakusWeb.Depot.ReceiptText do
  @moduledoc """
  A receipt's text in pieces, `{:text, text}` and `{:mark, text}`, with the values the model
  recognised marked where the text has them, see `Abakus.Depot.Receipts.Matching`.
  """

  alias Abakus.Depot.Receipts.{Fields, Matching}

  def pieces(nil, _fields), do: []
  def pieces(text, nil), do: [{:text, text}]

  def pieces(text, %Fields{} = fields) do
    case Matching.regex(fields) do
      nil -> [{:text, text}]
      regex -> split(text, regex)
    end
  end

  defp split(text, regex) do
    regex
    |> Regex.split(text, include_captures: true)
    |> Enum.with_index()
    |> Enum.reject(fn {piece, _index} -> piece == "" end)
    |> Enum.map(fn
      {piece, index} when rem(index, 2) == 1 -> {:mark, piece}
      {piece, _index} -> {:text, piece}
    end)
  end
end

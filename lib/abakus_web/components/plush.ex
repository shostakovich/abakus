defmodule AbakusWeb.Plush do
  @moduledoc """
  The plush images for Setzkasten's `<.plush>`, the shell's nav entries and area switch,
  `<.dropdown>` items and `<.empty_state plush="…">`: one WebP per motif in
  `priv/static/images/plush`, named after its Lucide icon, the same in both themes.
  """
  @behaviour Setzkasten.Plush

  @names ~w(activity archive baby banknote briefcase car clipboard-list coins file-text gift
            graduation-cap heart house inbox key landmark layers link palette paw-print
            piggy-bank plane receipt repeat scale settings shield shirt shopping-cart smartphone
            tag ticket trending-up users utensils wallet zap)

  @doc "The motifs there are images of."
  def names, do: @names

  @impl true
  def src(name, :light) when name in @names,
    do: AbakusWeb.Endpoint.static_path("/images/plush/#{name}.webp")

  def src(_name, _variant), do: nil
end

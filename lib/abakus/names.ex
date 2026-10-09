defmodule Abakus.Names do
  @moduledoc """
  Lookup keys for names that usually start with an emoji ("🛒 Lebensmittel"): lookups by name match without the
  emoji and ignoring case.
  """

  # Keycap sequences ("1️⃣") go as a whole; then symbols, pictographs, skin tones, regional indicators (flags), ZWJ,
  # variation selectors, the combining keycap and tag characters (subdivision flags).
  defp emoji do
    ~r/
      [0-9#*]\x{FE0F}?\x{20E3}
      | [\p{So}\p{Extended_Pictographic}\p{Emoji_Modifier}\p{Regional_Indicator}]
      | [\x{200D}\x{FE0E}\x{FE0F}\x{20E3}\x{E0020}-\x{E007F}]
    /ux
  end

  # What an emoji-only name drops: the variation selectors and skin tones.
  defp variant, do: ~r/[\x{FE0E}\x{FE0F}\x{1F3FB}-\x{1F3FF}]/u

  defp whitespace, do: ~r/\s+/u

  @doc """
  The key a name is looked up by: without emoji and symbols, whitespace collapsed, downcased, with "ß" as "ss".
  Composed and decomposed umlauts give the same key.

  A name that consists of emoji only keeps them without variation selectors and skin tones ("❤️" is "❤",
  "👍🏽" is "👍"), so its key is never empty.

      iex> Abakus.Names.lookup_key("🛒 Lebensmittel")
      "lebensmittel"
      iex> Abakus.Names.lookup_key("👨‍👩‍👧 Familie")
      "familie"
  """
  def lookup_key(name) when is_binary(name) do
    name = :unicode.characters_to_nfc_binary(name)

    with "" <- normalize(Regex.replace(emoji(), name, " ")),
         "" <- normalize(Regex.replace(variant(), name, "")) do
      normalize(name)
    end
  end

  defp normalize(name) do
    whitespace()
    |> Regex.replace(name, " ")
    |> String.trim()
    |> String.downcase()
    |> String.replace("ß", "ss")
  end

  @doc """
  Picks the one record a name means from `{record, preferred?}` pairs with the same lookup key, looking at the
  preferred ones first.
  """
  def pick(candidates) do
    preferred = for {record, true} <- candidates, do: record

    case if(preferred == [], do: Enum.map(candidates, &elem(&1, 0)), else: preferred) do
      [] -> {:error, :not_found}
      [record] -> {:ok, record}
      _ -> {:error, :ambiguous}
    end
  end

  @doc "Sets the `lookup_key` field from `name` whenever the name changes."
  def put_lookup_key(%Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.fetch_change(changeset, :name) do
      {:ok, name} when is_binary(name) ->
        Ecto.Changeset.put_change(changeset, :lookup_key, lookup_key(name))

      _ ->
        changeset
    end
  end
end

defmodule Abakus.NamesTest do
  use ExUnit.Case, async: true

  import Abakus.Names, only: [lookup_key: 1, pick: 1, split_emoji: 1]

  doctest Abakus.Names

  describe "lookup_key/1" do
    test "drops a leading emoji with or without a space" do
      assert lookup_key("🛒 Lebensmittel") == "lebensmittel"
      assert lookup_key("🎁Geschenke") == "geschenke"
      assert lookup_key("Lebensmittel 🛒") == "lebensmittel"
    end

    test "ignores case, keeping umlauts" do
      assert lookup_key("Lebensmittel") == lookup_key("LEBENSMITTEL")
      assert lookup_key("🚌 ÖFFIS") == "öffis"
    end

    test "folds ß into ss, as upper case spells it" do
      assert lookup_key("Straße") == "strasse"
      assert lookup_key("STRASSE") == lookup_key("Straße")
      assert lookup_key("STRAẞE") == lookup_key("Straße")
      assert lookup_key("🏠 Größere Ausgaben") == "grössere ausgaben"
    end

    test "treats composed and decomposed umlauts alike" do
      composed = "Caf\u00E9 M\u00FCller"
      decomposed = "Cafe\u0301 Mu\u0308ller"

      assert composed != decomposed
      assert lookup_key(decomposed) == lookup_key(composed)
      assert lookup_key("\u{1F6D2} " <> decomposed) == "caf\u00E9 m\u00FCller"
    end

    test "drops ZWJ sequences, skin tones and hair styles" do
      assert lookup_key("👨‍👩‍👧 Familie") == "familie"
      assert lookup_key("👍🏽 Gut") == "gut"
      assert lookup_key("🧑🏻‍🦰Friseur") == "friseur"
      assert lookup_key("👩‍💻 Arbeit") == "arbeit"
    end

    test "drops keycaps as a whole, keeping other digits" do
      assert lookup_key("1️⃣ Fixkosten") == "fixkosten"
      assert lookup_key("#️⃣ Sonstiges") == "sonstiges"
      assert lookup_key("*⃣ Stern") == "stern"
      assert lookup_key("🎄 Weihnachten 2026") == "weihnachten 2026"
    end

    test "drops flags and subdivision flags" do
      assert lookup_key("🇩🇪 Urlaub") == "urlaub"
      assert lookup_key("🇮🇹🇫🇷Reisen") == "reisen"
      assert lookup_key("🏴󠁧󠁢󠁳󠁣󠁴󠁿 Schottland") == "schottland"
    end

    test "drops variation selectors and text-style symbols" do
      assert lookup_key("❤️ Liebe") == "liebe"
      assert lookup_key("☕︎ Kaffee") == "kaffee"
      assert lookup_key("‼️ Wichtig") == "wichtig"
      assert lookup_key("ℹ️ Info") == "info"
      assert lookup_key("✈️Flüge") == "flüge"
    end

    test "collapses and trims whitespace, including emoji between words" do
      assert lookup_key("  Auto   🚗  Versicherung ") == "auto versicherung"
      assert lookup_key("Auto🚗Versicherung") == "auto versicherung"
      assert lookup_key("Bar geld\tund\nmehr") == "bar geld und mehr"
    end

    test "keeps punctuation and currency signs" do
      assert lookup_key("Inflow: Ready to Assign") == "inflow: ready to assign"
      assert lookup_key("Transfer : Girokonto") == "transfer : girokonto"
      assert lookup_key("💶 € Bargeld") == "€ bargeld"
    end

    test "keeps the emoji of a name that has nothing else" do
      assert lookup_key("🍕") == "🍕"
      assert lookup_key(" 🍕 ") == "🍕"
      assert lookup_key("🍕") != lookup_key("🍔")
    end

    test "ignores variation selectors and skin tones in a name of emoji only" do
      assert lookup_key("❤️") == lookup_key("❤")
      assert lookup_key("☕︎") == lookup_key("☕")
      assert lookup_key("👍🏽") == lookup_key("👍")
      assert lookup_key("👍🏻 ") == "👍"
      assert lookup_key("👨‍👩‍👧") != lookup_key("👨")
    end

    test "is the same for a word with any emoji, case and spacing" do
      emoji = ["🛒", "🎁", "👨‍👩‍👧", "👍🏽", "1️⃣", "🇩🇪", "❤️", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "🏖️"]

      words = [
        "Lebensmittel",
        "Geschenke",
        "Übrige Ausgaben",
        "Öffis",
        "Kfz-Steuer",
        "Haus & Garten"
      ]

      for _ <- 1..200 do
        word = Enum.random(words)
        decorated = Enum.random([word, String.upcase(word), String.downcase(word)])

        name =
          Enum.random(emoji) <>
            Enum.random(["", " ", "  "]) <> decorated <> Enum.random(["", " "])

        assert lookup_key(name) == String.downcase(word),
               "#{inspect(name)} → #{inspect(lookup_key(name))}"
      end
    end
  end

  describe "split_emoji/1" do
    test "splits off the leading emoji, ZWJ sequences and flags included" do
      assert split_emoji("🛒 Lebensmittel") == {"🛒", "Lebensmittel"}
      assert split_emoji("👨‍👩‍👧Familie") == {"👨‍👩‍👧", "Familie"}
      assert split_emoji("🇩🇪  Urlaub zu Hause") == {"🇩🇪", "Urlaub zu Hause"}
    end

    test "leaves a name without a leading emoji, or of emoji only, as it is" do
      assert split_emoji("Miete 🏠") == {nil, "Miete 🏠"}
      assert split_emoji("❤️") == {nil, "❤️"}
    end
  end

  describe "pick/1" do
    test "prefers the preferred candidates" do
      assert pick([]) == {:error, :not_found}
      assert pick([{:hidden, false}]) == {:ok, :hidden}
      assert pick([{:hidden, false}, {:visible, true}]) == {:ok, :visible}
      assert pick([{:a, false}, {:b, false}]) == {:error, :ambiguous}
      assert pick([{:a, true}, {:b, true}, {:c, false}]) == {:error, :ambiguous}
    end
  end
end

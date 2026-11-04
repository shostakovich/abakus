import AbakusCore
import Testing

@Suite struct LookupKeyTests {
    @Test(arguments: [
        ("🛒 Lebensmittel", "lebensmittel"),
        ("👨‍👩‍👧 Familie", "familie"),
        ("  Straße   am  Markt ", "strasse am markt"),
        ("STRASSE", "strasse"),
        ("Bäckerei", "bäckerei"),
        ("Ba\u{308}ckerei", "bäckerei"),
        ("1️⃣ Erste Wahl", "erste wahl"),
        ("Urlaub 🇮🇹", "urlaub"),
        ("Café ☕️ Rösterei", "café rösterei"),
        ("Amazon ™", "amazon"),
    ])
    func dropsEmojiCaseSpacingAndSharpS(name: String, key: String) {
        #expect(name.lookupKey == key)
    }

    @Test func aNameOfEmojiOnlyKeepsThemWithoutVariantsOrSkinTones() {
        #expect("❤️".lookupKey == "❤")
        #expect("👍🏽".lookupKey == "👍")
        #expect("".lookupKey == "")
    }
}

@Suite struct LeadingEmojiTests {
    @Test(arguments: [
        ("🛒 Lebensmittel", "🛒", "Lebensmittel"),
        ("👨‍👩‍👧 Familie", "👨‍👩‍👧", "Familie"),
        ("1️⃣ Erste Wahl", "1️⃣", "Erste Wahl"),
        ("💶💳Karten", "💶💳", "Karten"),
    ])
    func splitsTheLeadingEmojiFromTheName(name: String, emoji: String, rest: String) {
        #expect(name.leadingEmoji?.emoji == emoji)
        #expect(name.leadingEmoji?.name == rest)
    }

    @Test(arguments: ["Girokonto", "Urlaub 🇮🇹", "❤️", "🛒 ", "1 Konto", ""])
    func aNameWithoutLeadingEmojiOrOfEmojiOnlyHasNone(name: String) {
        #expect(name.leadingEmoji == nil)
    }
}

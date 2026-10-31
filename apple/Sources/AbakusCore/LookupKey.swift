import Foundation

extension String {
    /// Abakus's `Names.lookup_key`, so both apps find the same payee for a name.
    public var lookupKey: String {
        let composed = precomposedStringWithCanonicalMapping
        if composed.utf8.allSatisfy({ $0 < 0x80 }) { return LookupKey.normalize(composed.unicodeScalars) }
        let scalars = Array(composed.unicodeScalars)
        let withoutEmoji = LookupKey.normalize(LookupKey.replacingEmoji(scalars))
        guard withoutEmoji.isEmpty else { return withoutEmoji }
        let withoutVariants = LookupKey.normalize(scalars.filter { !LookupKey.isVariant($0) })
        return withoutVariants.isEmpty ? LookupKey.normalize(scalars) : withoutVariants
    }
}

private enum LookupKey {
    static func normalize(_ scalars: some Sequence<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in scalars {
            if scalar.properties.isWhitespace {
                pendingSpace = !view.isEmpty
                continue
            }
            if pendingSpace { view.append(" ") }
            pendingSpace = false
            view.append(scalar)
        }
        return String(view).lowercased().replacingOccurrences(of: "ß", with: "ss")
    }

    static func replacingEmoji(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        var index = 0
        while index < scalars.count {
            if let end = keycapEnd(scalars, from: index) {
                result.append(" ")
                index = end
            } else {
                result.append(isEmoji(scalars[index]) ? " " : scalars[index])
                index += 1
            }
        }
        return result
    }

    private static func keycapEnd(_ scalars: [Unicode.Scalar], from index: Int) -> Int? {
        guard "0123456789#*".unicodeScalars.contains(scalars[index]) else { return nil }
        var next = index + 1
        if next < scalars.count && scalars[next].value == 0xFE0F { next += 1 }
        return next < scalars.count && scalars[next].value == 0x20E3 ? next + 1 : nil
    }

    private static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        let value = scalar.value
        return properties.generalCategory == .otherSymbol || properties.isEmojiModifier
            || (properties.isEmoji && !scalar.isASCII)
            || (properties.generalCategory == .unassigned && (0x1F000...0x1FFFD).contains(value))
            || [0x200D, 0xFE0E, 0xFE0F, 0x20E3].contains(value) || (0xE0020...0xE007F).contains(value)
    }

    static func isVariant(_ scalar: Unicode.Scalar) -> Bool {
        [0xFE0E, 0xFE0F].contains(scalar.value) || (0x1F3FB...0x1F3FF).contains(scalar.value)
    }
}

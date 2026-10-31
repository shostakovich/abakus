import SwiftUI

/// Dialog and search suggestion texts carry `<b>`, `<i>`, `<br/>` and entities.
enum TextMarkup {
    struct Run: Equatable {
        var text: String
        var bold: Bool
        var italic: Bool
    }

    static func runs(_ markup: String) -> [Run] {
        var result: [Run] = []
        var bold = false
        var italic = false
        var rest = Substring(markup.replacingOccurrences(of: "<br/>", with: "\n"))
        while !rest.isEmpty {
            if rest.hasPrefix("<b>") || rest.hasPrefix("</b>") {
                bold = rest.hasPrefix("<b>")
                rest = rest.dropFirst(bold ? 3 : 4)
                continue
            }
            if rest.hasPrefix("<i>") || rest.hasPrefix("</i>") {
                italic = rest.hasPrefix("<i>")
                rest = rest.dropFirst(italic ? 3 : 4)
                continue
            }
            let end = rest.dropFirst().firstIndex(of: "<") ?? rest.endIndex
            let chunk = rest[..<end].replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
            rest = rest[end...]
            result.append(Run(text: chunk, bold: bold, italic: italic))
        }
        return result
    }

    /// Emphasis only, so the text takes the font of the view that shows it.
    static func attributed(_ markup: String) -> AttributedString {
        var result = runs(markup).reduce(into: AttributedString()) { result, run in
            var piece = AttributedString(run.text)
            var intent = InlinePresentationIntent()
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            result += piece
        }
        while result.characters.last?.isNewline == true { result.characters.removeLast() }
        return result
    }

    static func plain(_ markup: String) -> String {
        runs(markup).map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

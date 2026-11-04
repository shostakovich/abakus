import AbakusCore
import SwiftUI

/// A status the native look draws as an SF Symbol, with the colour it carries and its VoiceOver label.
package struct StatusSymbol: Hashable {
    package var name: String
    package var color: Color
    package var label: String

    package init(name: String, color: Color, label: String) {
        self.name = name
        self.color = color
        self.label = label
    }

    package static let warning = "exclamationmark.triangle.fill"

    package static var transfer: StatusSymbol {
        StatusSymbol(name: "arrow.left.arrow.right", color: ThemeColor.secondaryText, label: "Umbuchung")
    }
}

extension ClearedStatus {
    package var symbol: StatusSymbol {
        switch self {
        case .cleared: StatusSymbol(name: "checkmark.circle.fill", color: ThemeColor.positive, label: "Gebucht")
        case .uncleared: StatusSymbol(name: "circle", color: ThemeColor.secondaryText, label: "Vorgemerkt")
        case .reconciled: StatusSymbol(name: "lock.fill", color: ThemeColor.positive, label: "Abgeglichen")
        }
    }
}

extension ErrorLevel {
    package var symbol: StatusSymbol? {
        switch self {
        case .none: nil
        case .error: StatusSymbol(name: "xmark.octagon.fill", color: ThemeColor.negative, label: "Fehler")
        case .forReview: StatusSymbol(name: "checkmark", color: ThemeColor.accent, label: "Bestätigen")
        case .needsCategory:
            StatusSymbol(name: StatusSymbol.warning, color: ThemeColor.warning, label: "Kategorie fehlt")
        }
    }
}

package struct StatusSymbolImage: View {
    let symbol: StatusSymbol
    var tint: Color?

    package init(symbol: StatusSymbol, tint: Color? = nil) {
        self.symbol = symbol
        self.tint = tint
    }

    package var body: some View {
        Image(systemName: symbol.name)
            .font(.system(size: RegisterGridStyle.symbolSize))
            .foregroundStyle(tint ?? symbol.color)
            .accessibilityLabel(symbol.label)
    }
}

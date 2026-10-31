import AbakusCore
import SwiftUI

/// A status the native look draws as an SF Symbol, with the colour it carries and its VoiceOver label.
struct StatusSymbol: Hashable {
    var name: String
    var color: Color
    var label: String

    static let warning = "exclamationmark.triangle.fill"

    static var transfer: StatusSymbol {
        StatusSymbol(name: "arrow.left.arrow.right", color: ThemeColor.secondaryText, label: "Umbuchung")
    }
}

extension ClearedStatus {
    func symbol(reconciling: Bool) -> StatusSymbol {
        switch self {
        case .cleared:
            StatusSymbol(
                name: "checkmark.circle.fill", color: reconciling ? ThemeColor.accent : ThemeColor.secondaryText,
                label: "Gebucht")
        case .uncleared: StatusSymbol(name: "circle", color: ThemeColor.secondaryText, label: "Vorgemerkt")
        case .reconciled: StatusSymbol(name: "lock.fill", color: ThemeColor.secondaryText, label: "Abgeglichen")
        }
    }
}

extension ErrorLevel {
    var symbol: StatusSymbol? {
        switch self {
        case .none: nil
        case .error: StatusSymbol(name: "xmark.octagon.fill", color: ThemeColor.negative, label: "Fehler")
        case .forReview: StatusSymbol(name: "circle.fill", color: ThemeColor.accent, label: "Zu bestätigen")
        case .needsCategory:
            StatusSymbol(name: StatusSymbol.warning, color: ThemeColor.warning, label: "Kategorie fehlt")
        }
    }
}

struct StatusSymbolImage: View {
    let symbol: StatusSymbol
    var tint: Color?

    var body: some View {
        Image(systemName: symbol.name)
            .font(.system(size: RegisterGridStyle.symbolSize))
            .foregroundStyle(tint ?? symbol.color)
            .accessibilityLabel(symbol.label)
    }
}

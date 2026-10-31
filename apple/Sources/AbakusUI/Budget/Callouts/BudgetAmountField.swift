import AbakusCore
import SwiftUI

/// An amount typed in a budget popover, with the currency symbol on the locale's side.
struct BudgetAmountField: View {
    static let width: CGFloat = 110

    let label: String
    @Binding var text: String
    let locale: FormatLocale
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            if locale.symbolOnLeft { Text(verbatim: locale.currencySymbol) }
            TextField(label, text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused(isFocused)
                .frame(width: Self.width)
            if !locale.symbolOnLeft { Text(verbatim: locale.currencySymbol) }
        }
    }
}

import AbakusCore
import SwiftUI

public struct RegisterAdjustmentHelp: Hashable, Sendable {
    public var transactionId: String
    public var message: String
}

extension RegisterViewModel {
    public var adjustmentHelp: RegisterAdjustmentHelp? {
        guard let slot = adjustmentHelpSlot, slot.visit == navigation.visit else { return nil }
        return slot.help
    }

    /// Alle Konten stays, every other view switches to the transaction's account.
    func showAdjustment(_ help: RegisterAdjustmentHelp) {
        guard let transaction = store.budget.transaction(withId: help.transactionId) else { return }
        if !isAllAccounts { navigation.selection = .account(transaction.accountId) }
        reveal(transaction.id)
        adjustmentHelpSlot = (navigation.visit, help)
    }

    public func adjustmentHelpDismissed() {
        adjustmentHelpSlot = nil
    }
}

struct AdjustmentHelpAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct AdjustmentHelpLayer: View {
    static let width: CGFloat = 280

    let model: RegisterViewModel
    let help: RegisterAdjustmentHelp
    let anchor: Anchor<CGRect>

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                AnchoredPopover(
                    side: .above, anchor: proxy[anchor], container: proxy.size,
                    dismissal: CalloutDismissal(closesOnClickOutside: true, dismiss: model.adjustmentHelpDismissed)
                ) { content }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TextMarkup.attributed(help.message))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button("Schließen", action: model.adjustmentHelpDismissed).buttonStyle(.link)
            }
        }
        .font(ThemeFont.body.font)
        .foregroundStyle(ThemeColor.text)
        .frame(width: Self.width, alignment: .leading)
    }
}

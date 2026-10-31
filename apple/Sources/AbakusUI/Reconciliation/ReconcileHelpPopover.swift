import AbakusCore
import SwiftUI

struct ReconcileHelpLayer: View {
    static let width: CGFloat = 340

    let reconciliation: RegisterReconciliationController
    let anchor: Anchor<CGRect>?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: reconciliation.reconcileHelpDismissed)
                AnchoredPopover(
                    side: .above, anchor: anchor.map { proxy[$0] } ?? SidebarView.fallbackAnchor(in: proxy),
                    container: proxy.size,
                    dismissal: CalloutDismissal(
                        closesOnClickOutside: false, dismiss: reconciliation.reconcileHelpDismissed)
                ) {
                    Text(TextMarkup.attributed(RegisterReconciliationController.reconcileHelpText))
                        .font(ThemeFont.body.font)
                        .foregroundStyle(ThemeColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: Self.width, alignment: .leading)
                }
            }
        }
    }
}

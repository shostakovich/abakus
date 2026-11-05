import SwiftUI

/// Why the edited cell refuses its text, below the cell at once; the cell keeps the keyboard and the clicks.
package struct BudgetAmountErrorBubble: View {
    static let width: CGFloat = 240

    let error: String
    let anchor: Anchor<CGRect>
    @State private var size = CGSize.zero

    package init(error: String, anchor: Anchor<CGRect>) {
        self.error = error
        self.anchor = anchor
    }

    package var body: some View {
        GeometryReader { proxy in
            let placement = PopoverPlacement.place(size, beside: proxy[anchor], on: .below, in: proxy.size)
            PopoverChrome(arrowEdge: placement.arrowEdge, arrowOffset: placement.arrowOffset) {
                Text(verbatim: error)
                    .font(Self.font)
                    .foregroundStyle(ThemeColor.negative)
                    .frame(width: Self.width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .opacity(size == .zero ? 0 : 1)
            .offset(x: placement.frame.minX, y: placement.frame.minY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    #if os(macOS)
        private static let font = ThemeFont.body.font
    #else
        private static let font = Font.footnote
    #endif
}

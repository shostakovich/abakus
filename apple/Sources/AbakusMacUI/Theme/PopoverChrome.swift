import AbakusUI
import SwiftUI

extension View {
    func systemMenuChrome(cornerRadius: CGFloat = SystemChrome.menuCornerRadius) -> some View {
        background(ThemeColor.windowBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(ThemeColor.separator, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    func focusRing(_ isShown: Bool, cornerRadius: CGFloat, color: Color = ThemeColor.focusRing) -> some View {
        overlay {
            if isShown {
                RoundedRectangle(cornerRadius: cornerRadius + SystemChrome.focusRingWidth)
                    .strokeBorder(color, lineWidth: SystemChrome.focusRingWidth)
                    .padding(-SystemChrome.focusRingWidth)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// An in-window popover that sizes itself to its content and stands beside its opener.
struct AnchoredPopover<Content: View>: View {
    let side: PopoverSide
    let anchor: CGRect
    let container: CGSize
    /// Watches the window's events itself, so it must see the popover's own frame, not the offset one.
    var dismissal: CalloutDismissal?
    @ViewBuilder let content: Content
    @State private var size = CGSize.zero

    var body: some View {
        let placement = PopoverPlacement.place(size, beside: anchor, on: side, in: container)
        dismissible(PopoverChrome(arrowEdge: placement.arrowEdge, arrowOffset: placement.arrowOffset) { content })
            .fixedSize()
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                size = $0
            }
            .opacity(size == .zero ? 0 : 1)
            .offset(x: placement.frame.minX, y: placement.frame.minY)
    }

    @ViewBuilder
    private func dismissible(_ chrome: some View) -> some View {
        if let dismissal { chrome.modifier(dismissal) } else { chrome }
    }
}

struct PopoverTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(verbatim: title)
            .font(ThemeFont.headline.font)
            .foregroundStyle(ThemeColor.text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A popover's actions in the look of menu items: the hovered one in the accent colour.
struct PopoverMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            let isLit = isHovered || configuration.isPressed
            configuration.label
                .foregroundStyle(foreground(isLit: isLit))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: SystemChrome.menuRowHeight, alignment: .leading)
                .background {
                    if isLit { RoundedRectangle(cornerRadius: 4).fill(ThemeColor.accent) }
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }

        private func foreground(isLit: Bool) -> AnyShapeStyle {
            if isLit { return AnyShapeStyle(ThemeColor.selectedText) }
            return configuration.role == .destructive
                ? AnyShapeStyle(ThemeColor.negative) : AnyShapeStyle(ThemeColor.text)
        }
    }
}

import SwiftUI

extension View {
    func systemMenuChrome(cornerRadius: CGFloat = SystemChrome.menuCornerRadius) -> some View {
        background(ThemeColor.windowBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(ThemeColor.separator, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    func floatingShadow() -> some View {
        compositingGroup().shadow(color: .black.opacity(0.22), radius: 12, y: 6)
    }

    func focusRing(_ isShown: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if isShown {
                RoundedRectangle(cornerRadius: cornerRadius + SystemChrome.focusRingWidth)
                    .strokeBorder(ThemeColor.focusRing, lineWidth: SystemChrome.focusRingWidth)
                    .padding(-SystemChrome.focusRingWidth)
                    .allowsHitTesting(false)
            }
        }
    }
}

enum SystemChrome {
    static let menuCornerRadius: CGFloat = 8
    static let menuPadding: CGFloat = 5
    static let menuRowHeight: CGFloat = 22
    static let focusRingWidth: CGFloat = 3
}

enum PopoverMetrics {
    static let arrowHeight: CGFloat = 8
    static let arrowWidth: CGFloat = 18
    static let cornerRadius: CGFloat = 10
    static let padding: CGFloat = 12

    static func size(content size: CGSize, padding: CGFloat = padding) -> CGSize {
        CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding + arrowHeight)
    }
}

enum PopoverSide {
    case below, above, trailing
}

struct PopoverPlacement: Equatable {
    var frame: CGRect
    /// The edge the arrow sits on: `.top` for a popover below its opener.
    var arrowEdge: Edge
    /// The arrow's tip along that edge, from the popover's top or leading corner.
    var arrowOffset: CGFloat

    /// Beside the opener on `side`, flipped above or below when only the other side has room, and on the side with
    /// more room when neither has enough; the arrow points at the opener's centre.
    static func place(_ size: CGSize, beside anchor: CGRect, on side: PopoverSide, in container: CGSize)
        -> PopoverPlacement
    {
        switch side {
        case .below, .above:
            let top = max(0, anchor.maxY)
            let fitsBelow = top + size.height <= container.height
            let fitsAbove = anchor.minY >= size.height
            let below: Bool
            switch (fitsBelow, fitsAbove) {
            case (true, true): below = side == .below
            case (false, false): below = container.height - top >= anchor.minY
            case (let fits, _): below = fits
            }
            let x = max(0, min(anchor.midX - size.width / 2, container.width - size.width))
            let y = below ? top : anchor.minY - size.height
            return PopoverPlacement(
                frame: CGRect(origin: CGPoint(x: x, y: y), size: size), arrowEdge: below ? .top : .bottom,
                arrowOffset: anchor.midX - x)
        case .trailing:
            let y = max(0, min(anchor.midY - size.height / 2, container.height - size.height))
            return PopoverPlacement(
                frame: CGRect(origin: CGPoint(x: anchor.maxX, y: y), size: size), arrowEdge: .leading,
                arrowOffset: anchor.midY - y)
        }
    }

    /// Cut to the container's height on the side away from the opener, for a popover whose content scrolls.
    func fitting(in container: CGSize) -> PopoverPlacement {
        var fitted = self
        switch arrowEdge {
        case .top: fitted.frame.size.height = min(frame.height, max(container.height - frame.minY, 0))
        case .bottom:
            fitted.frame.origin.y = max(frame.minY, 0)
            fitted.frame.size.height = frame.maxY - fitted.frame.minY
        case .leading, .trailing: break
        }
        return fitted
    }
}

/// A popover drawn inside the window, so the field that opened it keeps the keyboard; its arrow points at the opener.
struct PopoverChrome<Content: View>: View {
    let arrowEdge: Edge
    let arrowOffset: CGFloat
    var padding = PopoverMetrics.padding
    @ViewBuilder let content: Content

    var body: some View {
        let shape = PopoverShape(arrowEdge: arrowEdge, arrowOffset: arrowOffset)
        content
            .padding(padding)
            .padding(Edge.Set(arrowEdge), PopoverMetrics.arrowHeight)
            .background(ThemeColor.windowBackground, in: shape)
            .overlay { shape.stroke(ThemeColor.separator, lineWidth: 0.5) }
            .floatingShadow()
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

private struct PopoverShape: Shape {
    let arrowEdge: Edge
    let arrowOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        let arrow = PopoverMetrics.arrowHeight
        let halfWidth = PopoverMetrics.arrowWidth / 2
        let radius = PopoverMetrics.cornerRadius
        var body = rect
        switch arrowEdge {
        case .top: body = CGRect(x: rect.minX, y: rect.minY + arrow, width: rect.width, height: rect.height - arrow)
        case .bottom: body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - arrow)
        case .leading: body = CGRect(x: rect.minX + arrow, y: rect.minY, width: rect.width - arrow, height: rect.height)
        case .trailing: body = CGRect(x: rect.minX, y: rect.minY, width: rect.width - arrow, height: rect.height)
        }
        let length = arrowEdge == .top || arrowEdge == .bottom ? rect.width : rect.height
        let tip = min(max(arrowOffset, radius + halfWidth), length - radius - halfWidth)
        let points: [CGPoint]
        switch arrowEdge {
        case .top:
            points = [
                CGPoint(x: tip - halfWidth, y: body.minY + 0.5), CGPoint(x: tip, y: rect.minY),
                CGPoint(x: tip + halfWidth, y: body.minY + 0.5),
            ]
        case .bottom:
            points = [
                CGPoint(x: tip - halfWidth, y: body.maxY - 0.5), CGPoint(x: tip, y: rect.maxY),
                CGPoint(x: tip + halfWidth, y: body.maxY - 0.5),
            ]
        case .leading:
            points = [
                CGPoint(x: body.minX + 0.5, y: tip - halfWidth), CGPoint(x: rect.minX, y: tip),
                CGPoint(x: body.minX + 0.5, y: tip + halfWidth),
            ]
        case .trailing:
            points = [
                CGPoint(x: body.maxX - 0.5, y: tip - halfWidth), CGPoint(x: rect.maxX, y: tip),
                CGPoint(x: body.maxX - 0.5, y: tip + halfWidth),
            ]
        }
        var arrowPath = Path()
        arrowPath.addLines(points)
        arrowPath.closeSubpath()
        return Path(roundedRect: body, cornerRadius: radius).union(arrowPath)
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

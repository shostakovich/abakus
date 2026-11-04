import SwiftUI

package enum SystemChrome {
    package static let menuCornerRadius: CGFloat = 8
    package static let menuPadding: CGFloat = 5
    package static let menuRowHeight: CGFloat = 22
    package static let focusRingWidth: CGFloat = 3
}

package enum PopoverMetrics {
    package static let arrowHeight: CGFloat = 8
    package static let arrowWidth: CGFloat = 18
    package static let cornerRadius: CGFloat = 10
    package static let padding: CGFloat = 12

    package static func size(content size: CGSize, padding: CGFloat = padding) -> CGSize {
        CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding + arrowHeight)
    }
}

package enum PopoverSide {
    case below, above, trailing
}

package struct PopoverPlacement: Equatable {
    package var frame: CGRect
    /// The edge the arrow sits on: `.top` for a popover below its opener.
    package var arrowEdge: Edge
    /// The arrow's tip along that edge, from the popover's top or leading corner.
    package var arrowOffset: CGFloat

    package init(frame: CGRect, arrowEdge: Edge, arrowOffset: CGFloat) {
        self.frame = frame
        self.arrowEdge = arrowEdge
        self.arrowOffset = arrowOffset
    }

    /// Beside the opener on `side`, flipped above or below (or to the leading side) when only the other side has
    /// room, and above or below on the side with more room when neither has enough; the arrow points at the opener's
    /// centre.
    package static func place(_ size: CGSize, beside anchor: CGRect, on side: PopoverSide, in container: CGSize)
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
            let leading = anchor.maxX + size.width > container.width && anchor.minX >= size.width
            return PopoverPlacement(
                frame: CGRect(origin: CGPoint(x: leading ? anchor.minX - size.width : anchor.maxX, y: y), size: size),
                arrowEdge: leading ? .trailing : .leading, arrowOffset: anchor.midY - y)
        }
    }

    /// Cut to the container's height on the side away from the opener, for a popover whose content scrolls.
    package func fitting(in container: CGSize) -> PopoverPlacement {
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

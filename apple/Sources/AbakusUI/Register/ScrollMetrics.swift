import SwiftUI

public struct ScrollMetrics: Hashable, Sendable {
    public var offset: CGFloat
    public var contentHeight: CGFloat
    public var viewportHeight: CGFloat

    public init(offset: CGFloat = 0, contentHeight: CGFloat = 0, viewportHeight: CGFloat = 0) {
        self.offset = offset
        self.contentHeight = contentHeight
        self.viewportHeight = viewportHeight
    }

    public var maxOffset: CGFloat { max(0, contentHeight - viewportHeight) }
    public var canScroll: Bool { maxOffset > 0.5 }
    public var isAtEnd: Bool { offset >= maxOffset - 0.5 }

    package func hasSameSize(as other: ScrollMetrics) -> Bool {
        abs(contentHeight - other.contentHeight) < 1 && abs(viewportHeight - other.viewportHeight) < 1
    }
}

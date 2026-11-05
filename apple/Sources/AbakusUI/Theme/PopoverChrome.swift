import SwiftUI

extension View {
    package func floatingShadow() -> some View {
        compositingGroup().shadow(color: .black.opacity(0.22), radius: 12, y: 6)
    }
}

/// A popover drawn inside the window, so the field that opened it keeps the keyboard; its arrow points at the opener.
package struct PopoverChrome<Content: View>: View {
    let arrowEdge: Edge
    let arrowOffset: CGFloat
    let padding: CGFloat
    let background: AnyShapeStyle
    let content: Content

    package init(
        arrowEdge: Edge, arrowOffset: CGFloat, padding: CGFloat = PopoverMetrics.padding,
        background: AnyShapeStyle = AnyShapeStyle(ThemeColor.windowBackground), @ViewBuilder content: () -> Content
    ) {
        self.arrowEdge = arrowEdge
        self.arrowOffset = arrowOffset
        self.padding = padding
        self.background = background
        self.content = content()
    }

    package var body: some View {
        let shape = PopoverShape(arrowEdge: arrowEdge, arrowOffset: arrowOffset)
        content
            .padding(padding)
            .padding(Edge.Set(arrowEdge), PopoverMetrics.arrowHeight)
            .background(background, in: shape)
            .overlay { shape.stroke(ThemeColor.separator, lineWidth: 0.5) }
            .floatingShadow()
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

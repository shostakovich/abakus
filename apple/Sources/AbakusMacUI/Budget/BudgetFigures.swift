import AbakusUI
import SwiftUI

/// A figure whose digits end at the cell's padding; a trailing € hangs past the digits.
struct BudgetFigure: View {
    let text: String
    var font = BudgetStyle.assignedFont
    var style: AnyShapeStyle = AnyShapeStyle(ThemeColor.text)
    var suffix = ""

    var body: some View {
        Text(verbatim: text)
            .font(font.font)
            .foregroundStyle(style)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .overlay(alignment: .trailing) {
                if !suffix.isEmpty {
                    Text(verbatim: suffix)
                        .font(BudgetStyle.columnTitleFont.font)
                        .foregroundStyle(ThemeColor.secondaryText)
                        .fixedSize()
                        .offset(x: BudgetStyle.columnTitleFont.width(of: suffix) + 1)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// A borderless symbol button with a hit area of at least 20 pt and a VoiceOver label.
struct BudgetSymbolButton: View {
    nonisolated static let size: CGFloat = 22

    let symbol: String
    let label: String
    var toolTip: String?
    var style: AnyShapeStyle = AnyShapeStyle(ThemeColor.secondaryText)
    var rotation: Angle = .zero
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: BudgetStyle.symbolSize))
                .foregroundStyle(style)
                .rotationEffect(rotation)
                .frame(width: Self.size, height: Self.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .toolTip(toolTip)
    }
}

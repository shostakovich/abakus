import SwiftUI

enum BudgetStyle {
    static let nameFont = ThemeFont.table
    static let masterFont = ThemeFont.tableEmphasized
    static let assignedFont = ThemeFont.table
    static let outflowsFont = ThemeFont.table
    static let balanceFont = ThemeFont.tableMedium
    static let overspentFont = ThemeFont.tableEmphasized
    static let masterNegativeFont = ThemeFont.tableMedium
    static let columnTitleFont = ThemeFont(size: 12)
    static let totalFont = ThemeFont(size: 13, weight: .semibold, hasTabularDigits: true)
    static let monthTitleFont = ThemeFont(size: 17, weight: .bold)
    static let availableFont = ThemeFont(size: 26, weight: .semibold, hasTabularDigits: true)
    static let detailFont = ThemeFont(size: 11, hasTabularDigits: true)
    static let detailAmountFont = ThemeFont(size: 11, weight: .medium, hasTabularDigits: true)

    static let zero: some ShapeStyle = HierarchicalShapeStyle.quaternary
    static let cardCornerRadius: CGFloat = 10
    static let tableCornerRadius: CGFloat = 10
    static let fieldCornerRadius: CGFloat = 5
    static let nameX: CGFloat = 30
    static let symbolSize: CGFloat = 12
    static let markerSize: CGFloat = 11
    static let markerSpacing: CGFloat = 4

    static let groupResize = Motion(.easeInOut, .milliseconds(250), .movement)
    static let headerResize = Motion(.easeInOut, .milliseconds(200), .movement)
    static let indicatorMove = Motion(.easeOut, .milliseconds(250), .movement)
}

/// A figure whose digits end at the cell's padding; a zero is a faint 0,00 and a trailing € hangs past the digits.
struct BudgetFigure: View {
    let text: String
    let zero: String
    var font = BudgetStyle.assignedFont
    var style: AnyShapeStyle = AnyShapeStyle(ThemeColor.text)
    var suffix = ""

    private var isZero: Bool { text.isEmpty || text == zero }

    var body: some View {
        Text(verbatim: isZero ? zero : text)
            .font(isZero ? BudgetStyle.assignedFont.font : font.font)
            .foregroundStyle(isZero ? AnyShapeStyle(BudgetStyle.zero) : style)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: BudgetStyle.symbolSize))
                .foregroundStyle(style)
                .frame(width: Self.size, height: Self.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .toolTip(toolTip)
    }
}

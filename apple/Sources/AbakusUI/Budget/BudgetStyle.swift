import SwiftUI

enum BudgetStyle {
    static let nameFont = ThemeFont.table
    static let masterFont = ThemeFont.tableEmphasized
    static let assignedFont = ThemeFont.table
    static let outflowsFont = ThemeFont.table
    static let balanceFont = ThemeFont.tableEmphasized
    static let columnTitleFont = ThemeFont(size: 11)
    static let totalFont = ThemeFont(size: 13, weight: .semibold, hasTabularDigits: true)
    static let monthTitleFont = ThemeFont(size: 14, weight: .semibold)
    static let resultLabelFont = ThemeFont(size: 11, weight: .medium)
    static let resultFont = ThemeFont(size: 18, weight: .bold, hasTabularDigits: true)
    static let detailFont = ThemeFont(size: 11, hasTabularDigits: true)
    static let detailAmountFont = ThemeFont(size: 11, weight: .medium, hasTabularDigits: true)

    static let tableCornerRadius: CGFloat = 10
    static let fieldCornerRadius: CGFloat = 5
    static let resultCornerRadius: CGFloat = 6
    /// The month title and the Zu verteilen band start at the same inset, as on the web.
    static let resultInset: CGFloat = 8
    static let resultPadding: CGFloat = 10
    static let columnHeadBottomPadding: CGFloat = 4
    /// Laid over the group band in Verfügbar, as the web mixes the two.
    static let groupAvailableTintOpacity = 0.4
    static let nameX: CGFloat = 30
    static let symbolSize: CGFloat = 12
    static let markerSize: CGFloat = 11
    static let ringSize: CGFloat = 12
    static let ringLineWidth: CGFloat = 2
    static let markerSpacing: CGFloat = 4
    /// Behind every Verfügbar figure, so the digits line up whether a row has a marker or not.
    static let markerSlot: CGFloat = ringSize + markerSpacing
    static let markerInset: CGFloat = 6
    static let availableDigitInset = markerInset + markerSlot

    static let groupResize = Motion(.easeInOut, .milliseconds(250), .movement)
    static let headerResize = Motion(.easeInOut, .milliseconds(200), .movement)
    static let indicatorMove = Motion(.easeOut, .milliseconds(250), .movement)
}

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

/// How much of an underfunded target's month is funded: a track and an arc clockwise from 12 o'clock.
struct BudgetTargetRing: View {
    let percent: Int
    let color: Color

    var body: some View {
        let width = BudgetStyle.ringLineWidth
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: width)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(width / 2)
        .frame(width: BudgetStyle.ringSize, height: BudgetStyle.ringSize)
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

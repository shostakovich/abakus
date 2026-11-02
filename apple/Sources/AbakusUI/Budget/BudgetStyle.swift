import SwiftUI

package enum BudgetStyle {
    package static let nameFont = ThemeFont.table
    package static let masterFont = ThemeFont.tableEmphasized
    package static let assignedFont = ThemeFont.table
    package static let outflowsFont = ThemeFont.table
    package static let balanceFont = ThemeFont.tableEmphasized
    package static let columnTitleFont = ThemeFont(size: 11)
    package static let totalFont = ThemeFont(size: 13, weight: .semibold, hasTabularDigits: true)
    package static let monthTitleFont = ThemeFont(size: 14, weight: .semibold)
    package static let resultLabelFont = ThemeFont(size: 11, weight: .medium)
    package static let resultFont = ThemeFont(size: 18, weight: .bold, hasTabularDigits: true)
    package static let detailFont = ThemeFont(size: 11, hasTabularDigits: true)
    package static let detailAmountFont = ThemeFont(size: 11, weight: .medium, hasTabularDigits: true)

    package static let tableCornerRadius: CGFloat = 10
    package static let fieldCornerRadius: CGFloat = 5
    package static let resultCornerRadius: CGFloat = 6
    /// The month title and the Zu verteilen band start at the same inset, as on the web.
    package static let resultInset: CGFloat = 8
    package static let resultPadding: CGFloat = 10
    package static let columnHeadBottomPadding: CGFloat = 4
    /// Laid over the group band in Verfügbar, as the web mixes the two.
    package static let groupAvailableTintOpacity = 0.4
    package static let nameX: CGFloat = 30
    package static let symbolSize: CGFloat = 12
    package static let markerSize: CGFloat = 11
    package static let ringSize: CGFloat = 12
    package static let ringLineWidth: CGFloat = 2
    static let markerSpacing: CGFloat = 4
    /// Behind every Verfügbar figure, so the digits line up whether a row has a marker or not.
    package static let markerSlot: CGFloat = ringSize + markerSpacing
    package static let markerInset: CGFloat = 6
    package static let availableDigitInset = markerInset + markerSlot

    package static let groupResize = Motion(.easeInOut, .milliseconds(250), .movement)
    package static let headerResize = Motion(.easeInOut, .milliseconds(200), .movement)
    package static let indicatorMove = Motion(.easeOut, .milliseconds(250), .movement)
}

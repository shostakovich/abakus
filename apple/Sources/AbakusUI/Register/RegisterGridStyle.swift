import SwiftUI

package enum RegisterGridStyle {
    package static let headerFont = ThemeFont(size: ThemeFont.caption.size, weight: .medium)
    package static let rowFont = ThemeFont.table
    package static let rowBoldFont = ThemeFont.tableEmphasized
    package static let monthHeadingFont = ThemeFont(size: ThemeFont.caption.size, weight: .semibold)
    package static let symbolSize: CGFloat = 13
    package static let cellInset: CGFloat = 6
    static let sortIndicatorWidth: CGFloat = 12
    package static let subRowIndent: CGFloat = 14
    package static let addedRowCanvas = ThemeColor.accent.opacity(0.15)
    package static let adjustmentRow = ThemeColor.accent.opacity(0.15)
    package static let addedRowGlow = ThemeColor.accent
}

extension RegisterColumn {
    /// The wider of the header and the widest cell plus `accessory`, never under the column's minimum.
    func contentWidth(fitting texts: [String], accessory: CGFloat = 0) -> CGFloat {
        let headerWidth: CGFloat =
            switch header {
            case .text(let title): RegisterGridStyle.headerFont.width(of: title) + RegisterGridStyle.sortIndicatorWidth
            case .symbol: 0
            }
        let cellWidth = texts.map { RegisterGridStyle.rowFont.width(of: $0) + accessory }.max() ?? 0
        return max(minWidth, ceil(max(headerWidth, cellWidth) + 2 * RegisterGridStyle.cellInset))
    }
}

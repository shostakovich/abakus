import CoreGraphics

package enum EditCellStyle {
    package static let font = ThemeFont.table
    package static let fieldCornerRadius: CGFloat = 5
    package static let fieldInset: CGFloat = 2
    package static let textInset: CGFloat = 6
    package static let accessoryWidth: CGFloat = 18
    /// The calculator and the sign button at an amount field's start.
    static let amountAccessoriesWidth: CGFloat = 2 * accessoryWidth
}

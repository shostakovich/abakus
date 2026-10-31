import AppKit
import SwiftUI

/// SwiftUI's own styles wherever one exists: `Color(nsColor:)` ignores Increase Contrast.
public enum ThemeColor {
    public static let text = Color.primary
    public static let secondaryText = Color.secondary
    public static let tertiaryText = HierarchicalShapeStyle.tertiary
    public static let accent = Color.accentColor
    public static let selectedText = Color.white
    public static let separator = SeparatorShapeStyle()
    public static let windowBackground = WindowBackgroundShapeStyle()
    public static let contentBackground = Color(nsColor: .controlBackgroundColor)
    public static let groupFill: some ShapeStyle = FillShapeStyle().quaternary
    /// The edited row: a neutral selection, so the accent stays with the focused field.
    public static let selectionBand: some ShapeStyle = FillShapeStyle().tertiary
    public static let fieldBackground = Color(nsColor: .textBackgroundColor)
    public static let fieldOutline: some ShapeStyle = HierarchicalShapeStyle.quaternary
    public static let focusRing = Color(nsColor: .keyboardFocusIndicatorColor)
    public static let negative = Color.red
    /// Only a figure of exactly zero, such as a fully assigned month.
    public static let balanced = Color.green
    public static let warning = Color.orange
    public static let positive = Color.green
}

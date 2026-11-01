import AppKit
import SwiftUI

/// The native look's text styles in the system font; table styles keep digits tabular so amounts line up.
public struct ThemeFont: Hashable, Sendable {
    public let size: CGFloat
    public let weight: NSFont.Weight
    public let hasTabularDigits: Bool

    public init(size: CGFloat, weight: NSFont.Weight = .regular, hasTabularDigits: Bool = false) {
        self.size = size
        self.weight = weight
        self.hasTabularDigits = hasTabularDigits
    }

    public var nsFont: NSFont {
        hasTabularDigits
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    }

    public var font: Font { Font(nsFont) }

    public func width(of text: String) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: nsFont]).size().width)
    }
}

extension ThemeFont {
    public static let headline = ThemeFont(size: NSFont.systemFontSize, weight: .semibold)
    public static let body = ThemeFont(size: NSFont.systemFontSize)
    public static let caption = ThemeFont(size: NSFont.smallSystemFontSize)
    public static let table = ThemeFont(size: 14, hasTabularDigits: true)
    public static let tableMedium = ThemeFont(size: 14, weight: .medium, hasTabularDigits: true)
    public static let tableEmphasized = ThemeFont(size: 14, weight: .semibold, hasTabularDigits: true)
}

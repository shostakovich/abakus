import SwiftUI

#if os(macOS)
    import AppKit
    typealias PlatformFont = NSFont
#else
    import UIKit
    typealias PlatformFont = UIFont
#endif

/// The native look's text styles in the system font; table styles keep digits tabular so amounts line up.
public struct ThemeFont: Hashable, Sendable {
    #if os(macOS)
        public typealias Weight = NSFont.Weight
    #else
        public typealias Weight = UIFont.Weight
    #endif

    public let size: CGFloat
    public let weight: Weight
    public let hasTabularDigits: Bool

    public init(size: CGFloat, weight: Weight = .regular, hasTabularDigits: Bool = false) {
        self.size = size
        self.weight = weight
        self.hasTabularDigits = hasTabularDigits
    }

    #if os(macOS)
        public var nsFont: NSFont { platformFont }
    #else
        public var uiFont: UIFont { platformFont }
    #endif

    private var platformFont: PlatformFont {
        hasTabularDigits
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    }

    public var font: Font { Font(platformFont as CTFont) }

    public func width(of text: String) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: platformFont]).size().width)
    }
}

extension ThemeFont {
    public static let headline = ThemeFont(size: PlatformFont.systemFontSize, weight: .semibold)
    public static let body = ThemeFont(size: PlatformFont.systemFontSize)
    public static let caption = ThemeFont(size: PlatformFont.smallSystemFontSize)
    public static let table = ThemeFont(size: 14, hasTabularDigits: true)
    public static let tableMedium = ThemeFont(size: 14, weight: .medium, hasTabularDigits: true)
    public static let tableEmphasized = ThemeFont(size: 14, weight: .semibold, hasTabularDigits: true)
}

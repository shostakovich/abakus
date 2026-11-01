import AppKit
import SwiftUI

/// Abakus's colours come from Setzkasten's tokens; text, separators and backgrounds stay the system's, as SwiftUI's own
/// styles follow Increase Contrast and `Color(nsColor:)` does not.
public enum ThemeColor {
    public static let text = Color.primary
    public static let secondaryText = Color.secondary
    public static let tertiaryText = HierarchicalShapeStyle.tertiary
    public static let accent = SetzkastenToken.primary.color
    /// Text on an accent fill, such as a highlighted menu item.
    public static let selectedText = SetzkastenToken.primaryContent.color
    public static let separator = SeparatorShapeStyle()
    public static let windowBackground = WindowBackgroundShapeStyle()
    public static let contentBackground = Color(nsColor: .controlBackgroundColor)
    public static let groupFill: some ShapeStyle = FillShapeStyle().quaternary
    public static let groupBand = SetzkastenToken.base200.color
    public static let availableTint = SetzkastenToken.availableTint.color
    public static let positiveBand = SetzkastenToken.successBand.color
    /// Selected rows and the edited row; the accent stays with the focused field.
    public static let selection = SetzkastenToken.rowSelected.color
    public static let fieldBackground = Color(nsColor: .textBackgroundColor)
    public static let fieldOutline: some ShapeStyle = HierarchicalShapeStyle.quaternary
    public static let focusRing = Color(nsColor: .keyboardFocusIndicatorColor)
    public static let negative = SetzkastenToken.errorInk.color
    public static let warning = SetzkastenToken.warningInk.color
    public static let positive = SetzkastenToken.successInk.color
}

/// A colour as CSS writes it in OKLCH: lightness in percent, chroma and hue in degrees.
public struct OKLCH: Hashable, Sendable {
    public let lightness: Double
    public let chroma: Double
    public let hue: Double

    public init(_ lightness: Double, _ chroma: Double, _ hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    /// Gamma-encoded extended sRGB: a component outside 0...1 is a colour beyond sRGB that a P3 display still shows.
    public var sRGB: (red: Double, green: Double, blue: Double) {
        let radians = hue * .pi / 180
        let (l, a, b) = (lightness / 100, chroma * cos(radians), chroma * sin(radians))
        let long = pow(l + 0.396_337_777_4 * a + 0.215_803_757_3 * b, 3)
        let medium = pow(l - 0.105_561_345_8 * a - 0.063_854_172_8 * b, 3)
        let short = pow(l - 0.089_484_177_5 * a - 1.291_485_548_0 * b, 3)
        return (
            Self.encoded(4.076_741_662_1 * long - 3.307_711_591_3 * medium + 0.230_969_929_2 * short),
            Self.encoded(-1.268_438_004_6 * long + 2.609_757_401_1 * medium - 0.341_319_396_5 * short),
            Self.encoded(-0.004_196_086_3 * long - 0.703_418_614_7 * medium + 1.707_614_701_0 * short)
        )
    }

    public var nsColor: NSColor {
        let rgb = sRGB
        return NSColor(colorSpace: .extendedSRGB, components: [rgb.red, rgb.green, rgb.blue, 1], count: 4)
    }

    private static func encoded(_ linear: Double) -> Double {
        let magnitude = abs(linear)
        let encoded = magnitude <= 0.003_130_8 ? 12.92 * magnitude : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
        return linear < 0 ? -encoded : encoded
    }
}

/// A token of Setzkasten's `zipfel` theme with its light and dark value, copied from `setzkasten.css`.
public struct SetzkastenToken: Hashable, Sendable {
    public let light: OKLCH
    public let dark: OKLCH

    public var color: Color {
        let light = light.nsColor
        let dark = dark.nsColor
        return Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
    }

    /// For a view that draws in another appearance than the window, such as the sidebar.
    public func color(for scheme: ColorScheme) -> Color {
        Color(nsColor: (scheme == .dark ? dark : light).nsColor)
    }
}

extension SetzkastenToken {
    static let primary = Self(light: OKLCH(54.52, 0.129, 241.86), dark: OKLCH(76.88, 0.129, 242.25))
    static let primaryContent = Self(light: OKLCH(100, 0, 0), dark: OKLCH(21.89, 0.055, 245.19))
    static let base200 = Self(light: OKLCH(97.70, 0.006, 239.82), dark: OKLCH(29.50, 0.010, 262.00))
    static let rowSelected = Self(light: OKLCH(96.00, 0.021, 240.00), dark: OKLCH(33.50, 0.030, 248.00))
    static let successInk = Self(light: OKLCH(52.13, 0.144, 149.89), dark: OKLCH(81.97, 0.170, 150.02))
    static let warningInk = Self(light: OKLCH(54.00, 0.114, 74.60), dark: OKLCH(86.93, 0.142, 84.86))
    static let errorInk = Self(light: OKLCH(54.94, 0.199, 25.12), dark: OKLCH(74.93, 0.151, 21.82))
    static let warning = Self(light: OKLCH(86.00, 0.154, 85.00), dark: OKLCH(86.93, 0.142, 84.86))
    static let warningContent = Self(light: OKLCH(26.94, 0.060, 60.30), dark: OKLCH(26.00, 0.059, 60.77))
    static let sidebar = Self(light: OKLCH(34.05, 0.035, 255.32), dark: OKLCH(20.00, 0.010, 262.00))
    static let sidebarContent = Self(light: OKLCH(98.07, 0.005, 247.88), dark: OKLCH(95.07, 0.005, 247.88))
    static let sidebarMuted = Self(light: OKLCH(83.02, 0.024, 250.11), dark: OKLCH(79.07, 0.010, 258.34))
    static let sidebarAccent = Self(light: OKLCH(79.98, 0.108, 245.09), dark: OKLCH(75.90, 0.128, 250.16))
    static let sidebarNegative = Self(light: OKLCH(81.00, 0.095, 22.00), dark: OKLCH(74.93, 0.151, 21.82))
    /// Not in Setzkasten: the web's budget sets the Verfügbar column on it.
    static let availableTint = Self(light: OKLCH(97.20, 0.008, 240.00), dark: OKLCH(27.50, 0.010, 262.00))
    /// Not in Setzkasten: the web's budget sets Zu verteilen above zero on it.
    static let successBand = Self(light: OKLCH(96.00, 0.035, 150.00), dark: OKLCH(30.00, 0.040, 150.00))
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

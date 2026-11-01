import AppKit
import SwiftUI
import Testing

@testable import AbakusUI

@MainActor
@Suite struct NativeThemeTests {
    @Test(arguments: [ThemeFont.table, ThemeFont.tableMedium, ThemeFont.tableEmphasized])
    func tableStylesAre14PointWithTabularDigits(style: ThemeFont) {
        #expect(style.nsFont.pointSize == 14)
        #expect(style.width(of: "1.111,11€") == style.width(of: "8.888,88€"))
    }

    @Test func tableWeightsGrowFromRegularToEmphasized() {
        #expect(ThemeFont.table.width(of: "Groceries") < ThemeFont.tableMedium.width(of: "Groceries"))
        #expect(ThemeFont.tableMedium.width(of: "Groceries") < ThemeFont.tableEmphasized.width(of: "Groceries"))
    }

    @Test func textStylesFollowTheSystemSizes() {
        #expect(ThemeFont.largeTitle.nsFont.pointSize == NSFont.preferredFont(forTextStyle: .largeTitle).pointSize)
        #expect(ThemeFont.body.nsFont.pointSize == NSFont.systemFontSize)
        #expect(ThemeFont.caption.nsFont.pointSize == NSFont.smallSystemFontSize)
    }

    @Test(arguments: [ThemeColor.text, ThemeColor.secondaryText])
    func textFollowsDarkModeAndIncreaseContrast(color: Color) {
        let light = color.resolve(in: environment(.light, .standard))
        #expect(light != color.resolve(in: environment(.dark, .standard)))
        #expect(light != color.resolve(in: environment(.light, .increased)))
    }

    @Test(arguments: [
        (OKLCH(34.05, 0.035, 255.32), 0x2c394a), (OKLCH(98.07, 0.005, 247.88), 0xf6f9fc),
        (OKLCH(83.02, 0.024, 250.11), 0xbcc9d7), (OKLCH(79.98, 0.108, 245.09), 0x80c5ff),
        (OKLCH(81.00, 0.095, 22.00), 0xf8a9a5), (OKLCH(100, 0, 0), 0xffffff),
    ])
    func oklchMatchesTheHexSetzkastenNotes(color: OKLCH, hex: Int) {
        let rgb = color.sRGB
        let channels = [rgb.red, rgb.green, rgb.blue].map { Int(($0 * 255).rounded()) }
        #expect(channels == [hex >> 16 & 0xff, hex >> 8 & 0xff, hex & 0xff])
    }

    @Test func abakusColoursAreSetzkastenTokensInBothAppearances() {
        let tokens: [(Color, SetzkastenToken)] = [
            (ThemeColor.accent, .primary), (ThemeColor.negative, .errorInk), (ThemeColor.warning, .warningInk),
            (ThemeColor.positive, .successInk),
            (ThemeColor.selection, .rowSelected),
            (ThemeColor.groupBand, .base200), (ThemeColor.availableTint, .availableTint),
            (ThemeColor.positiveBand, .successBand),
            (ThemeColor.selectedText, .primaryContent),
        ]
        for (color, token) in tokens {
            for scheme in [ColorScheme.light, .dark] {
                let resolved = color.resolve(in: environment(scheme, .standard))
                #expect(resolved == token.color(for: scheme).resolve(in: environment(scheme, .standard)))
            }
        }
    }

    @Test func aTokenTellsLightFromDark() {
        let accent = ThemeColor.accent
        #expect(accent.resolve(in: environment(.light, .standard)) != accent.resolve(in: environment(.dark, .standard)))
    }

    private func environment(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        environment._colorSchemeContrast = contrast
        return environment
    }
}

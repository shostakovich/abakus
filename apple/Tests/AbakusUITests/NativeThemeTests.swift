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

    @Test(arguments: [ThemeColor.text, ThemeColor.secondaryText, ThemeColor.negative, ThemeColor.balanced])
    func coloursFollowDarkModeAndIncreaseContrast(color: Color) {
        let light = color.resolve(in: environment(.light, .standard))
        #expect(light != color.resolve(in: environment(.dark, .standard)))
        #expect(light != color.resolve(in: environment(.light, .increased)))
    }

    @Test func meaningfulColoursAreTheSystemOnes() {
        #expect(ThemeColor.negative == .red)
        #expect(ThemeColor.balanced == .green)
        #expect(ThemeColor.warning == .orange)
        #expect(ThemeColor.accent == .accentColor)
    }

    private func environment(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        environment._colorSchemeContrast = contrast
        return environment
    }
}

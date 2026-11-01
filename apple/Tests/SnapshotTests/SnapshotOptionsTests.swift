import AbakusUI
import AppKit
import SwiftUI
import Testing

@testable import Snapshot

@Suite struct SnapshotOptionsTests {
    @Test(arguments: [
        ["out.png", "--acount", "Girokonto"], ["out.png", "--native-menu"], ["out.png", "other.png"],
        ["out.png", "--account"], ["out.png", "--scale", "x"], ["out.png", "--scale", "0"],
        ["out.png", "--select", "x"], ["out.png", "--height", "x"], ["out.png", "--height", "-5"],
    ])
    func unknownFlagsAndBadValuesAreRejected(arguments: [String]) {
        #expect(throws: SnapshotError.self) { try SnapshotOptions(arguments: arguments) }
    }

    @Test func validValuesAreTaken() throws {
        let options = try SnapshotOptions(arguments: ["out.png", "--scale", "1", "--select", "2", "--height", "681"])
        #expect(options.output.lastPathComponent == "out.png")
        #expect(options.scale == 1)
        #expect(options.selectNewest == 2)
        #expect(options.height == 681)
    }

    @Test func budgetStatesTakeAMonthAndTheTestEdits() throws {
        let options = try SnapshotOptions(arguments: [
            "out.png", "--budget", "quick-budget", "--month", "2023-05", "--test-edits", "--width", "1344",
        ])
        #expect(options.budget == .quickBudget)
        #expect(options.month?.description == "2023-05-01")
        #expect(options.testEdits)
        #expect(options.width == 1344)
        for arguments in [
            ["out.png", "--budget", "nope"], ["out.png", "--budget", "screen", "--month", "2023-13"],
            ["out.png", "--month", "2023-05"], ["out.png", "--test-edits"], ["out.png", "--width", "0"],
        ] {
            #expect(throws: SnapshotError.self) { try SnapshotOptions(arguments: arguments) }
        }
    }

    @Test func everyBudgetStateIsAnOption() throws {
        for state in BudgetHarness.State.allCases {
            #expect(try SnapshotOptions(arguments: ["out.png", "--budget", state.rawValue]).budget == state)
        }
    }

    @Test(arguments: [
        ([String](), ColorScheme.light, ColorSchemeContrast.standard), (["--dark"], .dark, .standard),
        (["--increase-contrast"], .light, .increased), (["--dark", "--increase-contrast"], .dark, .increased),
    ])
    func anyStateRendersInLightDarkAndIncreaseContrast(
        flags: [String], scheme: ColorScheme, contrast: ColorSchemeContrast
    ) throws {
        let options = try SnapshotOptions(arguments: ["out.png", "--budget", "screen"] + flags)
        #expect(options.colorScheme == scheme)
        #expect(options.contrast == contrast)
    }

    @MainActor
    @Test func increaseContrastAlsoReachesAppKitDrawing() throws {
        let standard = try #require(appearance(.light, contrast: .standard))
        let increased = try #require(appearance(.dark, contrast: .increased))
        #expect(standard.name == .aqua)
        #expect(increased.name.rawValue == "DarkAquaAX")
    }

    @MainActor
    @Test func inlineMenusAreAsWideAsTheirLongestItem() {
        let long = "Total scheduled outflows this month"
        let items = [
            RegisterMenuItem(id: "title", title: "Fill in all empty budget cells with:", kind: .title),
            RegisterMenuItem(id: "long", title: long, kind: .title),
        ]
        let plain = InlineMenuMetrics(items)
        let width = NSAttributedString(string: long, attributes: [.font: NSFont.menuFont(ofSize: 0)]).size().width
        #expect(plain.size.width >= plain.textLeading + width)
    }

    @Test func nativeMenusOnlyRunWithTheKeyProbe() throws {
        #expect(throws: SnapshotError.self) {
            try SnapshotOptions(arguments: ["out.png", "--ops", "context-menu", "--native-menus"])
        }
        #expect(throws: SnapshotError.self) { try SnapshotOptions(arguments: ["out.png", "--native-menus"]) }
        #expect(try SnapshotOptions(arguments: ["out.png", "--ops", "keys", "--native-menus"]).nativeMenus)
    }
}

@Suite struct BlankCaptureTests {
    @Test func aUniformImageIsBlank() throws {
        #expect(isBlank(try image { _ in }))
    }

    @Test func anImageWithContentIsNot() throws {
        #expect(!isBlank(try image { $0.fill(CGRect(x: 40, y: 40, width: 20, height: 20)) }))
    }

    private func image(_ draw: (CGContext) -> Void) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        draw(context)
        return try #require(context.makeImage())
    }
}

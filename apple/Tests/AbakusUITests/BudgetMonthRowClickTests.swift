import AbakusCore
import AppKit
import SwiftUI
import Testing

@testable import AbakusUI

@MainActor
@Suite struct BudgetMonthRowClickTests {
    typealias F = BudgetScreenFixture

    @Test func aBlankActivityCellTakesClicksAcrossItsWidth() async throws {
        let model = F().model().model
        let october = day("2026-10-01")
        let month = try #require(model.month(october))
        let row = try #require(model.groups.flatMap(\.subs).first { $0.id == F.kleidung })
        #expect(model.subRowDisplay(row.id, in: month).outflows.isEmpty)
        let cells = BudgetCellColumns(width: 300)
        let content = BudgetMonthSubRow(model: model, month: month, row: row, cells: cells)
            .frame(width: cells.width, height: BudgetMetrics.rowHeight)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: cells.width, height: BudgetMetrics.rowHeight),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: content)
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        await settle(window)
        let point = NSPoint(x: cells.assigned + cells.outflows / 2, y: BudgetMetrics.rowHeight / 2)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
        }
        await settle(window)
        #expect(model.presentedPopup == .outflowHelp(month: october, categoryId: F.kleidung))
    }

    private func settle(_ window: NSWindow) async {
        for _ in 0..<5 {
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(15))
        }
    }
}

import AbakusCore
import AppKit
import SwiftUI
import Testing

@testable import AbakusUI

/// Content views under a popover layer in a window of their own; clicks go through `NSApp` like in the app.
@MainActor
private final class PopoverWindow {
    static let size = CGSize(width: 900, height: 600)
    /// Far from every opener and popover.
    static let outside = CGPoint(x: 880, y: 580)

    let window: NSWindow
    private let clicks: ClickCounter

    var clicksBelow: Int { clicks.count }

    init<Content: View>(@ViewBuilder _ content: (ClickCounter) -> Content) {
        let clicks = ClickCounter()
        self.clicks = clicks
        let host = NSHostingView(rootView: content(clicks).frame(width: Self.size.width, height: Self.size.height))
        host.frame = CGRect(origin: .zero, size: Self.size)
        window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.alphaValue = 0
        window.orderFrontRegardless()
    }

    func settle() async {
        for _ in 0..<6 {
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    /// A left click at a top-left point of the content.
    func click(_ point: CGPoint) async {
        let location = NSPoint(x: point.x, y: Self.size.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(event)
        }
        await settle()
    }

    func close() {
        window.orderOut(nil)
    }
}

@MainActor
private final class ClickCounter {
    var count = 0
}

/// What lies under the popover: it counts the clicks that reach it, and places the opener at 200, 200.
private struct Underlay<Opener: View>: View {
    let clicks: ClickCounter
    @ViewBuilder let opener: Opener

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white.contentShape(Rectangle()).onTapGesture { clicks.count += 1 }
            opener.frame(width: 24, height: 24).offset(x: 200, y: 200)
        }
    }
}

@MainActor
@Suite(.serialized) struct RegisterPopoverOutsideClickTests {
    private func register(_ popup: (String) -> RegisterPopup?) -> (RegisterViewModel, PopoverWindow) {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -12, approved: false)
        let model = fixture.model()
        let window = PopoverWindow { clicks in
            Underlay(clicks: clicks) {
                Color.clear
                    .registerAnchor(.error(id))
                    .registerAnchor(.balance(id))
                    .registerAnchor(.schedulerTitle)
            }
            .overlayPreferenceValue(RegisterAnchorKey.self) { anchors in
                RegisterOverlayLayer(model: model, anchors: anchors, toolbarAnchors: ToolbarAnchors())
            }
        }
        if let popup = popup(id) { model.popup = popup }
        return (model, window)
    }

    @Test(arguments: [
        RegisterPopup.approveReject(rowId: ""), .needsCategory(rowId: ""), .removeCategory(rowId: ""),
    ])
    func aStatusPopoverClosesAndTakesTheClick(_ kind: RegisterPopup) async {
        let (model, window) = register { id in
            switch kind {
            case .needsCategory: .needsCategory(rowId: id)
            case .removeCategory: .removeCategory(rowId: id)
            default: .approveReject(rowId: id)
            }
        }
        defer { window.close() }
        await window.settle()
        await window.click(PopoverWindow.outside)
        #expect(model.popup == nil)
        #expect(window.clicksBelow == 0)
    }

    @Test func theTimeframeClosesWithoutApplyingAndTakesTheClick() async {
        let (model, window) = register { _ in nil }
        defer { window.close() }
        model.search.dateSelectorClicked()
        model.search.setTimeframeMonth(start: true, month: 5)
        await window.settle()
        await window.click(PopoverWindow.outside)
        #expect(model.popup == nil)
        #expect(model.search.timeframe == nil)
        #expect(model.search.dateFilter == nil)
        #expect(window.clicksBelow == 0)
    }

    @Test func theRunningBalanceStaysAndLetsTheClickThrough() async {
        let (model, window) = register { id in .runningBalance(rowId: id) }
        defer { window.close() }
        await window.settle()
        await window.click(PopoverWindow.outside)
        #expect(model.popup?.rowId != nil)
        #expect(window.clicksBelow == 1)
    }

    @Test func theScheduledCalloutStaysAndLetsTheClickThrough() async {
        let (model, window) = register { _ in .scheduledCallout(.added) }
        defer { window.close() }
        await window.settle()
        await window.click(PopoverWindow.outside)
        #expect(model.popup == .scheduledCallout(.added))
        #expect(window.clicksBelow == 1)
    }

    @Test func theAdjustmentHelpClosesAndLetsTheClickThrough() async throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -12)
        let model = fixture.model()
        model.showAdjustment(RegisterAdjustmentHelp(transactionId: id, message: "Adjusted"))
        let help = try #require(model.adjustmentHelp)
        let window = PopoverWindow { clicks in
            Underlay(clicks: clicks) {
                Color.clear.anchorPreference(key: AdjustmentHelpAnchorKey.self, value: .bounds) { $0 }
            }
            .overlayPreferenceValue(AdjustmentHelpAnchorKey.self) { anchor in
                if let anchor { AdjustmentHelpLayer(model: model, help: help, anchor: anchor) }
            }
        }
        defer { window.close() }
        await window.settle()
        await window.click(PopoverWindow.outside)
        #expect(model.adjustmentHelp == nil)
        #expect(window.clicksBelow == 1)
    }

    @Test func theReconcileHelpClosesAndTakesTheClick() async {
        let model = RegisterFixture().model()
        model.reconciliation.showsReconcileHelp = true
        let window = PopoverWindow { clicks in
            Underlay(clicks: clicks) {
                Color.clear.anchorPreference(key: AdjustmentHelpAnchorKey.self, value: .bounds) { $0 }
            }
            .overlayPreferenceValue(AdjustmentHelpAnchorKey.self) { anchor in
                if let anchor { ReconcileHelpLayer(reconciliation: model.reconciliation, anchor: anchor) }
            }
        }
        defer { window.close() }
        await window.settle()
        await window.click(PopoverWindow.outside)
        #expect(!model.reconciliation.showsReconcileHelp)
        #expect(window.clicksBelow == 0)
    }

    @Test func editAccountCancelsAndTakesTheClick() async throws {
        let fixture = RegisterFixture()
        let app = AppModel(store: BudgetStore(budget: fixture.budget, today: { editDay }), defaults: nil)
        app.accounts.editAccountRequested(fixture.giro)
        try #require(app.accounts.editForm).name = "Renamed"
        let window = PopoverWindow { clicks in
            Underlay(clicks: clicks) {
                Color.clear.anchorPreference(key: SidebarRowAnchorKey.self, value: .bounds) { [fixture.giro: $0] }
            }
            .overlayPreferenceValue(SidebarRowAnchorKey.self) { anchors in
                AccountEditLayer(controller: app.accounts, anchors: anchors)
            }
        }
        defer { window.close() }
        await window.settle()
        await window.click(PopoverWindow.outside)
        withKnownIssue("The macOS 26 runner drops the synthetic tap on the layer", isIntermittent: true) {
            #expect(app.accounts.editForm == nil)
        } when: {
            ProcessInfo.processInfo.environment["CI"] != nil
        }
        #expect(app.store.budget.account(withId: fixture.giro)?.name == "Giro")
        #expect(window.clicksBelow == 0)
    }
}

@Suite struct PopoverPlacementTests {
    private let container = CGSize(width: 800, height: 600)
    private let size = CGSize(width: 300, height: 200)

    @Test func belowPointsUpAtTheOpenersCentre() {
        let opener = CGRect(x: 400, y: 100, width: 40, height: 20)
        let placement = PopoverPlacement.place(size, beside: opener, on: .below, in: container)
        #expect(placement.arrowEdge == .top)
        #expect(placement.frame.minY == opener.maxY)
        #expect(placement.frame.minX + placement.arrowOffset == opener.midX)
    }

    @Test func aboveFlipsBelowWithoutRoomAndBelowFlipsAbove() {
        let high = CGRect(x: 400, y: 50, width: 40, height: 20)
        #expect(PopoverPlacement.place(size, beside: high, on: .above, in: container).arrowEdge == .top)
        let low = CGRect(x: 400, y: 500, width: 40, height: 20)
        let above = PopoverPlacement.place(size, beside: low, on: .below, in: container)
        #expect(above.arrowEdge == .bottom)
        #expect(above.frame.maxY == low.minY)
    }

    @Test func aPopoverStaysInTheContainerWhileItsArrowKeepsPointing() {
        let edge = CGRect(x: 780, y: 100, width: 20, height: 20)
        let placement = PopoverPlacement.place(size, beside: edge, on: .below, in: container)
        #expect(placement.frame.maxX == container.width)
        #expect(placement.frame.minX + placement.arrowOffset == edge.midX)
    }

    @Test func trailingPointsLeftAtTheOpenersMiddle() {
        let icon = CGRect(x: 200, y: 300, width: 20, height: 20)
        let placement = PopoverPlacement.place(size, beside: icon, on: .trailing, in: container)
        #expect(placement.arrowEdge == .leading)
        #expect(placement.frame.minX == icon.maxX)
        #expect(placement.frame.minY + placement.arrowOffset == icon.midY)
    }

    @Test func aToolbarOpenerPutsThePopoverAtTheTopOfTheContent() {
        let button = CGRect(x: 400, y: -30, width: 80, height: 24)
        let placement = PopoverPlacement.place(size, beside: button, on: .below, in: container)
        #expect(placement.frame.minY == 0)
        #expect(placement.arrowEdge == .top)
    }
}

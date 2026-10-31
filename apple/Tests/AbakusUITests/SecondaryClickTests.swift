import AbakusCore
import AppKit
import Foundation
import Testing

@testable import AbakusUI

@MainActor
private final class PresentedMenus {
    var points: [CGPoint] = []
}

@MainActor
@Suite struct SecondaryClickTests {
    private typealias CatcherView = SecondaryClickCatcher.CatcherView

    /// A 300 × 200 catcher whose presenter records where its menus open.
    private func catcher(menu: [RegisterMenuItem]?) -> (CatcherView, PresentedMenus) {
        let view = CatcherView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let presented = PresentedMenus()
        view.menuItems = { _ in menu }
        view.presenter = MenuPresenter { _, point, _, _ in presented.points.append(point) }
        return (view, presented)
    }

    /// A mouse-down 50 points from the left and 50 from the top of the catcher.
    private func mouseDown(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 50, y: 150), modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private let items = [RegisterMenuItem.action("Delete", .delete)]

    @Test func aRowMenuOpensOnePointRightOfAndBelowTheClick() throws {
        let (view, presented) = catcher(menu: items)
        view.rightMouseDown(with: try mouseDown(.rightMouseDown))
        view.mouseDown(with: try mouseDown(.leftMouseDown, modifiers: .control))
        #expect(presented.points == [CGPoint(x: 51, y: 51), CGPoint(x: 51, y: 51)])
    }

    @Test func theColumnMenuOpensOnePointBelowTheClick() throws {
        let (view, presented) = catcher(menu: items)
        view.offset = CGSize(width: 0, height: 1)
        view.rightMouseDown(with: try mouseDown(.rightMouseDown))
        #expect(presented.points == [CGPoint(x: 50, y: 51)])
    }

    @Test(arguments: [nil, []] as [[RegisterMenuItem]?])
    func noMenuOpensForAClickHandedOnOrTaken(_ menu: [RegisterMenuItem]?) throws {
        let (view, presented) = catcher(menu: menu)
        view.rightMouseDown(with: try mouseDown(.rightMouseDown))
        #expect(presented.points.isEmpty)
    }

    private func rows() -> (RegisterViewModel, [RegisterRow]) {
        var fixture = RegisterFixture()
        for (index, payee) in ["A", "B", "C"].enumerated() {
            fixture.add(fixture.giro, -1, on: "2014-05-1\(index)", payee: payee, category: fixture.groceries, id: payee)
        }
        let (model, _) = fixture.spied()
        return (model, model.rows)
    }

    private func row(atY y: CGFloat, in rows: [RegisterRow], scrollOffset: CGFloat = 0, tallRow: String? = nil)
        -> String?
    {
        RegisterGridController.row(
            atY: y, in: rows, scrollOffset: scrollOffset, editingId: tallRow, editRowExtraHeight: 40)?.id
    }

    @Test func theRowUnderAClickCountsTheScrollOffsetAndATallEditRow() {
        let (_, rows) = rows()
        let ids = rows.map(\.id)
        #expect(row(atY: 0, in: rows) == ids[0])
        #expect(row(atY: 27.5, in: rows) == ids[0])
        #expect(row(atY: 28, in: rows) == ids[1])
        #expect(row(atY: 0, in: rows, scrollOffset: 30) == ids[1])
        #expect(row(atY: 30, in: rows, scrollOffset: 30) == ids[2])
        #expect(row(atY: 50, in: rows, tallRow: ids[0]) == ids[0])
        #expect(row(atY: 68, in: rows, tallRow: ids[0]) == ids[1])
        #expect(row(atY: RegisterMetrics.rowHeight * CGFloat(rows.count), in: rows) == nil)
    }

    @Test func aClickOnARowOpensItsOwnersMenu() {
        let (model, rows) = rows()
        #expect(model.grid.contextMenu(atY: 30, scrollOffset: 0)?.first?.title == "1 ausgewählte Buchung:")
        #expect(model.selectedTransactionIds == [rows[1].transactionId])
    }

    @Test func aClickOnTheEditedRowOrBelowTheRowsIsHandedOn() throws {
        let (model, rows) = rows()
        model.beginEditing(rows[1].transactionId, column: .memo)
        let editor = try #require(model.editor)
        #expect(model.grid.contextMenu(atY: 30, scrollOffset: 0) == nil)
        #expect(model.grid.contextMenu(atY: 500, scrollOffset: 0) == nil)
        #expect(model.editor === editor)
        #expect(model.selectedTransactionIds == [rows[1].transactionId])
    }

    @Test func aClickThatAnEditSwallowsIsTaken() throws {
        let (model, rows) = rows()
        model.beginEditing(rows[1].transactionId, column: .memo)
        let editor = try #require(model.editor)
        editor.type("changed")
        let nextRow = RegisterMetrics.rowHeight + editor.rowHeight + 1
        #expect(model.grid.contextMenu(atY: nextRow, scrollOffset: 0) == [])
        #expect(editor.glowCount == 1)
        #expect(model.selectedTransactionIds == [rows[1].transactionId])
    }

    @Test func aClickUnderADialogIsTaken() {
        let (model, _) = rows()
        model.showMessage("Register", "")
        #expect(model.grid.contextMenu(atY: 30, scrollOffset: 0) == [])
        #expect(model.selection.isEmpty)
    }

    @Test func aScheduledRowOpensTheScheduledMenu() {
        var fixture = RegisterFixture()
        fixture.addSchedule("S1", category: fixture.groceries)
        let (model, _) = fixture.spied()
        let menu = model.scheduler.grid.contextMenu(atY: 10, scrollOffset: 0)
        #expect(menu?.first?.title == "1 ausgewählte geplante Buchung")
        #expect(model.scheduler.selectedIds == ["S1"])
    }
}

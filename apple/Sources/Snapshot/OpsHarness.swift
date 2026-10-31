import AbakusCore
import AbakusUI
import AppKit
import Carbon.HIToolbox
import Foundation

import struct SwiftUI.EventModifiers
import struct SwiftUI.KeyEquivalent

/// Puts the register into one of its operation states (menus, search, filters, notifiers) for a snapshot.
@MainActor
struct OpsHarness {
    enum State: String, CaseIterable {
        case actionMenu = "action-menu"
        case contextMenu = "context-menu"
        case searchSuggestions = "search-suggestions"
        case searchActive = "search-active"
        case dateFilter = "date-filter"
        case notifiers
        case columnMenu = "column-menu"
        case runningBalance = "running-balance"
        case approvePopup = "approve-popup"
        case needsCategory = "needs-category"
        case reconcileHelp = "reconcile-help"
        case deleteDialog = "delete-dialog"
        case makeRecurring = "make-recurring"
        case keys
    }

    let model: AppModel
    let edit: EditHarness
    /// nil with `--native-menus`, where the app pops its own menus.
    var menus: SnapshotMenus?

    private var register: RegisterViewModel { model.register }
    private var budget: Budget { model.store.budget }

    func run(_ state: State) throws {
        edit.settle()
        switch state {
        case .actionMenu:
            selectLast(3)
            register.editTransactionsClicked()
        case .contextMenu:
            try mouse([.rightMouseDown], on: .list, yFromTop: 420)
            print("right click -> selected \(register.selectedTransactionIds.count), menu \(menus?.shown != nil)")
            if menus?.shown == nil { throw SnapshotError.render }
        case .searchSuggestions:
            register.search.focus()
            edit.settle()
            edit.type("re")
            if register.search.text.isEmpty { register.search.boxChanged("re") }
        case .searchActive:
            register.search.run("Kategorie: Lebensmittel")
        case .dateFilter:
            register.search.dateSelectorClicked()
            register.search.timeframePresetClicked(.latestThreeMonths)
            edit.settle()
            register.search.dateSelectorClicked()
        case .notifiers:
            try addNotifierCases()
        case .columnMenu:
            register.columnOptionsClicked()
        case .runningBalance:
            register.performMenuAction(.toggleColumn(.runningBalance))
            edit.settle()
            let row = try lastRow { budget.payeeName(of: $0) == "Aral" }
            register.runningBalanceHovered(row, inside: true)
        case .approvePopup:
            try addUnapproved()
            edit.settle()
            let row = try lastRow { $0.needsApproval }
            register.errorIconClicked(row)
        case .needsCategory:
            register.errorIconClicked(try lastRow { budget.errorState(of: $0).level == .needsCategory })
        case .reconcileHelp:
            register.reconciliation.reconcileDisabledClicked()
            if !register.reconciliation.showsReconcileHelp { throw SnapshotError.render }
        case .deleteDialog:
            let transfer = try lastRow { budget.isTransfer($0) }
            register.rowClicked(transfer, column: nil, modifiers: .command)
            register.deleteTransactions(register.selectedTransactionIds)
        case .makeRecurring:
            selectLast(1)
            register.performMenuAction(.makeRecurring)
        case .keys:
            try probeKeys()
        }
        edit.settle()
    }

    private func probeKeys() throws {
        let row = try lastRow { budget.payeeName(of: $0) == "Telekom" }
        register.rowClicked(row, column: .payee, modifiers: [])
        edit.settle()
        let id = row.transactionId
        func cleared() -> String { budget.transaction(withId: id)?.cleared.rawValue ?? "-" }
        print("selected: \(register.selectedTransactionIds == [id]) cleared: \(cleared())")
        try menuKey("c", [.command, .shift])
        print("cmd-shift-c -> cleared: \(cleared())")
        try mouse([.leftMouseDown, .leftMouseUp], on: .list, yFromTop: 10)
        selectAll()
        print("cmd-a -> selected \(register.selection.count) of \(register.transactionIds.count)")
        register.rowClicked(row, column: .payee, modifiers: [])
        edit.settle()
        try menuKey("f", .command)
        print("cmd-f -> search focused: \(register.search.isFocused)")
        edit.type("tel")
        edit.key(kVK_DownArrow)
        edit.key(kVK_DownArrow)
        print(
            "typed '\(register.search.text)' -> highlighted \(register.search.dropDown?.highlighted.map(String.init) ?? "-")"
        )
        edit.key(kVK_Escape)
        print("escape -> drop-down open: \(register.search.dropDown != nil), text '\(register.search.text)'")
        edit.type(",")
        print("comma -> search '\(register.search.filter?.label ?? "-")', rows \(register.transactionIds.count)")
        print("grid has focus: \(!register.search.isFocused)")
        register.rowClicked(row, column: .payee, modifiers: [])
        edit.settle()
        edit.send("c", keyCode: UInt16(kVK_ANSI_C))
        edit.settle()
        print("c -> cleared: \(cleared())")
        edit.send("\u{7F}", keyCode: UInt16(kVK_Delete))
        edit.settle()
        print(
            "backspace -> deleted: \(budget.transaction(withId: id) == nil), undo: \(register.notifiers.undoSlot?.message ?? "-")"
        )
        try mouse([.leftMouseDown, .leftMouseUp], on: .header, yFromTop: 12, x: 100)
        print("header click -> ascending \(register.sortOrder.ascending)")
        print("click elsewhere -> undo: \(register.notifiers.undoSlot?.message ?? "-")")
        register.search.clearClicked()
        edit.settle()
        try post([.leftMouseDown, .leftMouseUp], at: NSPoint(x: 700, y: 45))
        print("summary click -> search '\(register.search.filter?.label ?? "-")'")
        var accounts: [String] = []
        for index in [1, 0] {
            try mouse([.leftMouseDown, .leftMouseUp], on: .sidebarRow(index), yFromTop: 12, x: 100)
            accounts.append(register.account?.name ?? "-")
            // A scheduler pane shown in one account only animates the switch, fading the grids over.
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
        print("sidebar clicks -> accounts \(accounts.joined(separator: ", "))")
        try mouse([.leftMouseDown, .leftMouseUp], on: .list, yFromTop: 10)
        print("row click -> selected \(register.selectedTransactionIds.count)")
        guard let menus else { return }
        var menu = try secondaryClick(on: .list, yFromTop: 40, menus: menus)
        print("row right click -> selected \(register.selectedTransactionIds.count), \(menu)")
        menu = try secondaryClick(on: .list, yFromTop: 64, control: true, menus: menus)
        print("row control-click -> selected \(register.selectedTransactionIds.count), \(menu)")
        register.search.run("Telekom")
        edit.settle()
        menu = try secondaryClick(on: .list, yFromTop: try yBelowTheLastRow(), menus: menus)
        print("right click below the last of \(register.transactionIds.count) rows -> \(menu)")
        register.search.clearClicked()
        edit.settle()
        if register.isSchedulerVisible {
            menu = try secondaryClick(on: .schedulerList, yFromTop: 12, menus: menus)
            print("scheduled row right click -> selected \(register.scheduler.selectedIds.count), \(menu)")
            let rightClicked = register.scheduler.selectedIds
            try mouse([.leftMouseDown, .leftMouseUp], on: .schedulerList, yFromTop: 36)
            let selected = register.scheduler.selectedIds
            print(
                "scheduled row click -> scheduler selected \(selected.count), another row: \(selected != rightClicked)")
            let ascending = register.scheduler.sortOrder.ascending
            try mouse([.leftMouseDown, .leftMouseUp], on: .schedulerHeader, yFromTop: 12, x: 60, modifiers: .control)
            print(
                "scheduler header control-click -> sort flipped: \(register.scheduler.sortOrder.ascending != ascending)"
            )
        }
        menus.reset()
        let click = try mouse([.rightMouseDown], on: .header, yFromTop: 10)
        print(
            "header right click -> column menu: \(menus.shown?.items.last?.title ?? "-")\(offset(of: menus, from: click))"
        )
    }

    /// Snapshot has no menu bar, so a key equivalent runs the Transactions menu command it belongs to.
    private func menuKey(_ key: KeyEquivalent, _ modifiers: SwiftUI.EventModifiers) throws {
        guard let command = RegisterCommand.matching(key, modifiers: modifiers) else { throw SnapshotError.render }
        command.perform(in: register)
        edit.settle()
    }

    /// Edit › Select All sends `selectAll:` to the first responder that takes it, as `NSApp.target(forAction:)`
    /// would in the key window; the offscreen window never becomes key.
    private func selectAll() {
        let action = #selector(NSResponder.selectAll(_:))
        var responder = edit.window.firstResponder
        while let current = responder {
            if let target = current.supplementalTarget(forAction: action, sender: nil)
                ?? (current.responds(to: action) ? current : nil)
            {
                NSApp.sendAction(action, to: target, from: nil)
                break
            }
            responder = current.nextResponder
        }
        edit.settle()
    }

    /// A right or Control-click on a catcher: the menu it opens, if any, and where relative to the click.
    private func secondaryClick(on catcher: Catcher, yFromTop: CGFloat, control: Bool = false, menus: SnapshotMenus)
        throws -> String
    {
        menus.reset()
        let click = try mouse(
            [control ? .leftMouseDown : .rightMouseDown], on: catcher, yFromTop: yFromTop,
            modifiers: control ? .control : [])
        return "menu '\(menus.shown?.items.first?.title ?? "-")'\(offset(of: menus, from: click))"
    }

    /// The shown menu's top-left corner relative to the click, both top-left origin.
    private func offset(of menus: SnapshotMenus, from click: NSPoint) -> String {
        guard let shown = menus.shown, let content = edit.window.contentView else { return "" }
        let local = content.convert(click, from: nil)
        let y = content.isFlipped ? local.y : content.bounds.height - local.y
        return String(format: " at %+g,%+g", shown.location.x - local.x, shown.location.y - y)
    }

    /// Below the add bar under the main list's last row.
    private func yBelowTheLastRow() throws -> CGFloat {
        let y = CGFloat(register.rows.count + 1) * RegisterMetrics.rowHeight + RegisterMetrics.rowHeight / 2
        guard y < (try frame(of: .list)).height else { throw SnapshotError.render }
        return y
    }

    private enum Catcher {
        case header, list, schedulerHeader, schedulerList
        case sidebarRow(Int)
    }

    /// Real mouse events at a point of a secondary-click catcher, measured from its top-left corner; returns the
    /// point in window coordinates.
    @discardableResult
    private func mouse(
        _ types: [NSEvent.EventType], on catcher: Catcher, yFromTop: CGFloat, x: CGFloat = 200,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSPoint {
        if !edit.window.isVisible {
            edit.window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            edit.window.orderFrontRegardless()
            edit.settle()
        }
        let frame = try frame(of: catcher)
        let point = NSPoint(x: frame.minX + x, y: frame.maxY - yFromTop)
        try post(types, at: point, modifiers: modifiers)
        return point
    }

    /// The register list's catcher is the tallest and each grid's header sits directly above its list; the
    /// scheduler's share the list's left edge further down, the sidebar rows' lie left of it.
    private func frame(of catcher: Catcher) throws -> NSRect {
        var frames: [NSRect] = []
        func collect(_ view: NSView) {
            // A former account's grid can stay in the tree, faded out.
            guard !view.isHidden, view.alphaValue > 0 else { return }
            if String(describing: type(of: view)) == "CatcherView" { frames.append(view.convert(view.bounds, to: nil)) }
            for subview in view.subviews { collect(subview) }
        }
        if let content = edit.window.contentView { collect(content) }
        let topDown = frames.sorted { $0.maxY > $1.maxY }
        guard let list = frames.max(by: { $0.height < $1.height }) else { throw SnapshotError.render }
        let schedulerList = topDown.last { $0.minX == list.minX && $0.maxY <= list.minY }
        func header(above list: NSRect?) -> NSRect? {
            list.flatMap { list in topDown.first { $0.minX == list.minX && abs($0.minY - list.maxY) < 0.5 } }
        }
        let found: NSRect? =
            switch catcher {
            case .list: list
            case .header: header(above: list)
            case .schedulerHeader: header(above: schedulerList)
            case .schedulerList: schedulerList
            case .sidebarRow(let index): topDown.filter { $0.maxX <= list.minX }[safe: index]
            }
        guard let found else { throw SnapshotError.render }
        return found
    }

    /// Through `NSApp.sendEvent`, so hit testing picks the views like in the app.
    private func post(_ types: [NSEvent.EventType], at location: NSPoint, modifiers: NSEvent.ModifierFlags = [])
        throws
    {
        for type in types {
            guard
                let event = NSEvent.mouseEvent(
                    with: type, location: location, modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: edit.window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else { throw SnapshotError.render }
            NSApp.postEvent(event, atStart: true)
            if let next = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(next)
            }
            edit.settle()
        }
    }

    private func selectLast(_ count: Int) {
        for id in register.transactionIds.suffix(count) {
            guard let row = register.rows.first(where: { $0.id == id }) else { continue }
            register.rowClicked(row, column: nil, modifiers: .command)
        }
    }

    private func lastRow(where predicate: (Transaction) -> Bool) throws -> RegisterRow {
        guard let transaction = register.transactions.last(where: predicate),
            let row = register.rows.first(where: { $0.id == transaction.id })
        else { throw SnapshotError.render }
        return row
    }

    private func addUnapproved() throws {
        guard let account = register.account else { throw SnapshotError.render }
        let transaction = Transaction(
            accountId: account.id, date: .today(), amount: -23.17, cleared: .cleared, approved: false,
            source: .bank)
        try model.store.perform(.addTransaction(transaction, payeeName: "REWE SAGT DANKE"))
    }

    /// An unapproved bank row, a categorised budget transfer and a delete: every notifier at once.
    private func addNotifierCases() throws {
        guard let account = register.account,
            let savings = budget.accounts.first(where: { $0.name == "Tagesgeld" }),
            let groceries = budget.category(fullName: "🛒 Alltag: 🛒 Lebensmittel")
        else { throw SnapshotError.render }
        try addUnapproved()
        try model.store.perform(
            .addTransaction(
                Transaction(
                    accountId: account.id, date: .today(), payeeId: EntityID.transferPayee(accountId: savings.id),
                    categoryId: groceries.id, amount: -25)))
        edit.settle()
        let victim = try lastRow { budget.payeeName(of: $0) == "Telekom" }
        register.rowClicked(victim, column: nil, modifiers: .command)
        register.deleteTransactions([victim.transactionId])
    }
}

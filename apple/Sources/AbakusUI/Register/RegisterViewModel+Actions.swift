import AbakusCore
import Foundation

enum DeleteChoice: Hashable, Sendable {
    case cancel, delete
}

enum CategorizeChoice: Hashable, Sendable {
    case cancel, categorize
}

enum UnlockChoice: Hashable, Sendable {
    case cancel, unlock
}

extension RegisterViewModel {
    var selectedTransactions: [Transaction] {
        let selection = selection
        return transactions.filter { selection.contains($0.id) }
    }

    /// The enable rules are recomputed on every open.
    public func transactionActionsMenu() -> [RegisterMenuItem] {
        transactionActionsMenu(of: selectedTransactions)
    }

    func transactionActionsMenu(of selected: [Transaction]) -> [RegisterMenuItem] {
        let budget = store.budget
        let led = budget.ledTransactionIds
        let unled = selected.filter { !led.contains($0.id) }
        let moveTargets = budget.moveTargets(excluding: account?.id)
        return [
            RegisterMenuItem(
                id: "categorize", title: "Kategorisieren als", kind: .submenu(categorizeItems),
                isEnabled: canCategorize),
            .separator(1),
            RegisterMenuItem(
                id: "move", title: "In Konto verschieben",
                kind: .submenu(moveTargets.map { .action($0.name, .moveToAccount(accountId: $0.id)) }),
                isEnabled: !moveTargets.isEmpty && !unled.isEmpty),
            .separator(3),
            .action("Löschen", .delete, enabled: !unled.isEmpty, isDestructive: isTouch),
        ]
    }

    var canCategorize: Bool { account?.onBudget ?? true }

    /// A master appears only when a category follows it.
    var categorizeItems: [RegisterMenuItem] {
        let catalog = DropDownCatalog(budget: store.budget, formatter: formatter, today: today())
        var groups: [(id: String, title: String, items: [RegisterMenuItem])] = []
        var master: (id: String, title: String)?
        for item in catalog.categoryItems(includeSplit: false) {
            switch item.kind {
            case .masterHeader: master = (item.id, item.label)
            case .category(let id, _, _, _):
                guard let master else { continue }
                if groups.last?.id != master.id { groups.append((master.id, master.title, [])) }
                groups[groups.count - 1].items.append(.action(item.label, .categorize(categoryId: id)))
            default: break
            }
        }
        let submenus = groups.map {
            RegisterMenuItem(id: "categorize:\($0.id)", title: $0.title, kind: .submenu($0.items))
        }
        return submenus + [.action("(Keine Kategorie)", .categorize(categoryId: nil))]
    }

    public var viewMenu: [RegisterMenuItem] {
        let closed = closedAccountsMenu
        return filterMenu + columnMenuItems.map { .action($0.label, .toggleColumn($0.column), checked: $0.isChecked) }
            + (closed.isEmpty ? [] : [.separator(20)] + closed)
    }

    /// A reconciliation sums what the list shows and hides the scheduled area, so it keeps Alle Buchungen.
    var filterMenu: [RegisterMenuItem] {
        guard !isReconciling else { return [] }
        let views = RegisterFilter.allCases.map {
            RegisterMenuItem.action($0.title, .filter($0), checked: $0 == filter)
        }
        let scheduled = schedulerMenu()
        return views + [.separator(10)] + (scheduled.isEmpty ? [] : scheduled + [.separator(12)])
    }

    /// While something is planned, its collapsed count shows the list instead.
    func schedulerMenu(systemImage: String? = nil) -> [RegisterMenuItem] {
        guard scheduler.count == 0 else { return [] }
        return [
            .action(RegisterScheduler.title, .toggleScheduler, checked: isSchedulerVisible, systemImage: systemImage)
        ]
    }

    /// „Ansicht: zu bestätigen“ while a view other than Alle Buchungen shows, as on the web.
    public var viewMenuTitle: String {
        guard filter != .all else { return "Ansicht" }
        return "Ansicht: " + filter.title.prefix(1).lowercased() + filter.title.dropFirst()
    }

    /// iOS names a view other than Alle Buchungen above the list, with the way back to it.
    public var activeViewLine: String? { filter == .all ? nil : viewMenuTitle }

    public static let allTransactionsTitle = RegisterFilter.all.title

    public func allTransactionsClicked() {
        viewMenuChosen(.filter(.all))
    }

    public var emptyListTitle: String {
        if search.isSearching { return "Keine Treffer" }
        return filter == .all ? "Keine Buchungen" : "Keine Buchungen in „\(filter.title)“"
    }

    func showMenu(_ items: [RegisterMenuItem], below anchor: RegisterAnchorID) {
        popup = nil
        menuRequest = RegisterMenuRequest(items: items, anchor: anchor)
    }

    public func menuDismissed() {
        menuRequest = nil
    }

    /// The row joins the selection, then the action menu opens.
    public func contextMenu(for row: RegisterRow) -> [RegisterMenuItem]? {
        guard !isBlockedByModal else { return nil }
        if grid.swallowsClick(on: row.transactionId) { return nil }
        closePopup()
        if !selection.contains(row.transactionId) { updateSelection { $0.select(row.transactionId) } }
        return transactionActionsMenu()
    }

    public func performMenuAction(_ action: RegisterMenuAction) {
        menuRequest = nil
        let selected = selectedTransactions
        let ids = selected.map(\.id)
        switch action {
        case .categorize(let categoryId): categorize(ids, categoryId: categoryId)
        case .moveToAccount(let accountId): moveTransactions(ids, to: accountId)
        case .delete: deleteTransactions(ids)
        case .filter(let filter): setFilter(filter)
        case .closedAccounts: closedAccountsClicked()
        case .togglePicking: togglePicking()
        case .toggleSelectAll: toggleSelectAll()
        case .toggleScheduler: scheduledToggleClicked()
        case .editAccount: onEditAccount()
        case .toggleColumn(let column): toggleColumnVisibility(column)
        case .toggleScheduledColumn(let column): scheduler.toggleColumnVisibility(column)
        case .applyScheduledColumnsToAllAccounts: scheduler.applyColumnSettingsToAllAccounts()
        case .enterScheduledNow: scheduler.enterNowClicked()
        case .skipScheduled: scheduler.skipClicked()
        case .deleteScheduled: scheduler.deleteClicked()
        case .moveScheduled(let accountId): scheduler.moveClicked(to: accountId)
        case .fillUnderfunded, .resetAssigned: break
        }
    }

    @discardableResult
    func perform(_ command: BudgetCommand) -> Bool {
        do {
            try store.perform(command)
            endEditsOvertakenByChanges()
            return true
        } catch let error as BudgetError where error.dialogContent != nil {
            showMessage(error.dialogInstruction, error.dialogContent ?? "")
            return false
        } catch {
            showMessage("Abakus", error.localizedDescription)
            return false
        }
    }

    public func closePopup() {
        popup = nil
    }

    /// Warnings need a confirmation, plain deletes happen at once.
    public func deleteTransactions(_ ids: [String]) {
        popup = nil
        guard !ids.isEmpty else { return }
        let analysis = store.budget.deleteAnalysis(ids)
        guard !analysis.deletable.isEmpty else {
            showMessage("Nichts gelöscht.", Self.nothingDeletedReason(analysis))
            return
        }
        let warnings = Self.deleteWarnings(analysis)
        guard !warnings.isEmpty else {
            performDelete(analysis.deletable)
            return
        }
        let deletable = analysis.deletable
        let count = deletable.count
        dialogs.ask(
            TaskDialog<DeleteChoice>(
                instruction: count == 1 ? "Buchung löschen?" : "\(count) Buchungen löschen?",
                content: warnings.joined(separator: "<br/><br/>"),
                buttons: [
                    .init(.cancel, title: "Abbrechen"),
                    .init(.delete, title: "Löschen", isDefault: true),
                ],
                dismissal: .cancel)
        ) { [weak self] answer in
            if answer.choice == .delete { self?.performDelete(deletable) }
        }
    }

    static func nothingDeletedReason(_ analysis: DeleteAnalysis) -> String {
        let leaders = TransactionLeader.byNames(analysis.leaders)
        if analysis.led == 0 {
            return "Alle ausgewählten Buchungen sind Gegenbuchungen von Teilen. Lösche sie in ihrer Aufteilung."
        }
        if analysis.transfersIntoSplits > 0 {
            return "Die ausgewählten Buchungen sind Gegenbuchungen von Teilen oder werden \(leaders) geführt."
        }
        return analysis.led == 1
            ? "Diese Buchung wird \(leaders) geführt und lässt sich hier nicht löschen."
            : "Diese Buchungen werden \(leaders) geführt und lassen sich hier nicht löschen."
    }

    static func deleteWarnings(_ analysis: DeleteAnalysis) -> [String] {
        var warnings: [String] = []
        if analysis.reconciled > 0 {
            let lead =
                analysis.reconciled == 1
                ? "1 der ausgewählten Buchungen ist abgeglichen. "
                : "\(analysis.reconciled) der ausgewählten Buchungen sind abgeglichen. "
            warnings.append(lead + "Ohne sie stimmt der abgeglichene Saldo nicht mehr.")
        }
        if analysis.otherSideReconciled > 0 {
            let lead =
                analysis.otherSideReconciled == 1
                ? "1 der ausgewählten Buchungen ist eine Umbuchung mit abgeglichener Gegenbuchung. "
                : "\(analysis.otherSideReconciled) der ausgewählten Buchungen sind Umbuchungen mit abgeglichener "
                    + "Gegenbuchung. "
            warnings.append(lead + "Ohne sie stimmt der abgeglichene Saldo des anderen Kontos nicht mehr.")
        }
        if analysis.transfersIntoSplits == 1 {
            warnings.append(
                "1 der ausgewählten Buchungen ist die Gegenbuchung eines Teils und wird nicht gelöscht. Lösche sie "
                    + "in ihrer Aufteilung.")
        } else if analysis.transfersIntoSplits > 1 {
            warnings.append(
                "\(analysis.transfersIntoSplits) der ausgewählten Buchungen sind Gegenbuchungen von Teilen und werden "
                    + "nicht gelöscht. Lösche sie in ihrer Aufteilung.")
        }
        let leaders = TransactionLeader.byNames(analysis.leaders)
        if analysis.led == 1 {
            warnings.append("1 der ausgewählten Buchungen wird \(leaders) geführt und nicht gelöscht.")
        } else if analysis.led > 1 {
            warnings.append("\(analysis.led) der ausgewählten Buchungen werden \(leaders) geführt und nicht gelöscht.")
        }
        if analysis.transfers > 0 {
            let lead =
                analysis.transfers == 1
                ? "1 der ausgewählten Buchungen ist eine Umbuchung. "
                : "\(analysis.transfers) der ausgewählten Buchungen sind Umbuchungen. "
            warnings.append(lead + "Ihre Gegenbuchung im anderen Konto wird mitgelöscht.")
        }
        return warnings
    }

    func performDelete(_ ids: [String]) {
        let before = store.budget
        guard perform(.deleteTransactions(ids)) else { return }
        let message = ids.count == 1 ? "Buchung gelöscht" : "\(ids.count) Buchungen gelöscht"
        let after = store.budget
        let remaining = Set(after.transactions.map(\.id))
        let payeeIds = Set(after.payees.map(\.id))
        let restore = RegisterUndoSlot.Restore.deleted(
            before.transactions.filter { !remaining.contains($0.id) },
            payees: before.payees.filter { !payeeIds.contains($0.id) })
        notifiers.offerUndo(message: message, restore: restore, reselect: ids)
    }

    func moveTransactions(_ selected: [String], to accountId: String) {
        let budget = store.budget
        let led = budget.ledTransactionIds
        let ids = selected.filter { !led.contains($0) }
        guard let target = budget.account(withId: accountId), !ids.isEmpty else { return }
        let wanted = Set(ids)
        let transactions = budget.transactions.filter { wanted.contains($0.id) }
        let refusal = BudgetError.transferIntoMoveTarget(target.name)
        let instruction = refusal.dialogInstruction
        if transactions.contains(where: { $0.transfers(into: accountId) }) {
            showMessage(instruction, refusal.dialogContent ?? "")
            return
        }
        let reconciled = transactions.count { $0.cleared == .reconciled }
        if reconciled > 1 {
            showMessage(
                instruction,
                "Mehrere dieser Buchungen sind abgeglichen. Verschiebe abgeglichene Buchungen einzeln.")
            return
        }
        if reconciled == 1 {
            dialogs.ask(
                .reconciledChange(
                    title: "Abgeglichene Buchung ändern",
                    content: "Diese Buchung ist abgeglichen. Mit anderem Konto stimmt der abgeglichene Saldo nicht "
                        + "mehr.")
            ) { [weak self] answer in
                if answer.choice == .change { self?.performMove(ids, to: accountId) }
            }
            return
        }
        performMove(ids, to: accountId)
    }

    func performMove(_ ids: [String], to accountId: String) {
        let before = store.budget
        guard let name = before.account(withId: accountId)?.name,
            perform(.moveTransactions(ids, toAccountId: accountId))
        else { return }
        let message =
            ids.count == 1
            ? "Buchung nach „\(name)“ verschoben" : "\(ids.count) Buchungen nach „\(name)“ verschoben"
        let wanted = Set(ids)
        let moved = before.transactions.filter { wanted.contains($0.id) }.map {
            MovedTransaction(transactionId: $0.id, accountId: $0.accountId, cleared: $0.cleared)
        }
        notifiers.offerUndo(message: message, restore: .moved(moved), reselect: ids)
    }

    func categorize(_ ids: [String], categoryId: String?) {
        let splits = selectedTransactions.count(where: \.isSplit)
        guard splits == 0 else {
            dialogs.ask(
                TaskDialog<CategorizeChoice>(
                    instruction: "Aufteilungen werden nicht kategorisiert.",
                    content: "Aufteilungen lassen sich nicht gemeinsam kategorisieren. Die \(splits) ausgewählten "
                        + "Aufteilungen werden übersprungen.",
                    buttons: [
                        .init(.cancel, title: "Abbrechen"),
                        .init(.categorize, title: "Trotzdem kategorisieren", isDefault: true),
                    ],
                    dismissal: .cancel)
            ) { [weak self] answer in
                if answer.choice == .categorize { self?.perform(.categorizeTransactions(ids, categoryId: categoryId)) }
            }
            return
        }
        perform(.categorizeTransactions(ids, categoryId: categoryId))
    }

    func showMessage(_ instruction: String, _ content: String) {
        dialogs.show(.message(instruction, content))
    }

    var isBlockedByModal: Bool {
        dialogs.isPresenting || editor?.addCategoryForm != nil || scheduler.editor != nil
            || reconciliation.statementForm != nil || isClosedAccountsListShown || isAppModalOpen()
    }

    /// Keys are ignored while a modal window or any popup is on screen.
    var acceptsRegisterKeys: Bool {
        !isBlockedByModal && popup == nil && menuRequest == nil
    }

    /// Delete, Backspace and Cmd+Delete: ignored in the search box and while a row is edited.
    public func deleteKeyPressed() {
        guard acceptsRegisterKeys, editor == nil, !search.isFocused else { return }
        deleteTransactions(selectedTransactionIds)
    }

    /// Cmd+A selects every row unless the search box has focus or a row is edited in either grid.
    public func selectAllKeyPressed() -> Bool {
        guard acceptsRegisterKeys, !grid.hasOpenEdit, !search.isFocused else { return false }
        selectAll()
        return true
    }

    public func refreshSort() {
        guard acceptsRegisterKeys else { return }
        requestScroll(selectedTransactionIds.first.map { .row($0) } ?? .top)
    }

    func jumpToOtherSide(of row: RegisterRow) {
        let budget = store.budget
        let counterpartId: String?
        if row.isSubtransaction {
            counterpartId =
                budget.transaction(withId: row.transactionId)?.subtransactions
                .first { $0.id == row.id }?.transferTransactionId
        } else {
            counterpartId = budget.transaction(withId: row.transactionId)?.transferTransactionId
        }
        guard let counterpartId else { return }
        let target =
            budget.transaction(withId: counterpartId)
            ?? budget.transactions.first { $0.subtransactions.contains { $0.id == counterpartId } }
        guard let target else { return }
        navigation.selection = .account(target.accountId)
        reveal(target.id)
    }

    func reveal(_ transactionId: String) {
        if !transactionIds.contains(transactionId) {
            search.cancel()
            setFilter(.all)
        }
        updateSelection { $0.select(transactionId) }
        requestScroll(.row(transactionId))
    }

    /// From the budget: the transaction's own account, also for a split line.
    public func showTransaction(_ transactionId: String) {
        guard let transaction = store.budget.transaction(withId: transactionId) else { return }
        navigation.selection = .account(transaction.accountId)
        reveal(transactionId)
    }

    public func showFilteredView(_ view: AccountViewFilter) {
        navigation.selection = view.accountId == EntityID.allAccounts ? .allAccounts : .account(view.accountId)
        setFilter(view.filter)
        search.run(view.searchText)
    }

    public func showAllAccounts(in filter: RegisterFilter) {
        showFilteredView(AccountViewFilter(accountId: EntityID.allAccounts, filter: filter))
    }

    public func showPayeeTransactions(_ payeeName: String, showingScheduled: Bool) {
        showFilteredView(AccountViewFilter(accountId: EntityID.allAccounts, searchText: payeeName))
        if showingScheduled && !isSchedulerVisible { scheduledToggleClicked() }
    }

    public func payeeSettingsShortcut() {
        onEditPayees(selectedTransactions.first.map { store.budget.payeeName(of: $0) })
    }
}

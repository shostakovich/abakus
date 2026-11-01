import AbakusCore
import AbakusUI
import AppKit
import Carbon.HIToolbox
import Foundation

/// The test budget "Business", today 24.10.2026.
enum BudgetReference {
    static let today = DateWithoutTime(year: 2026, month: 10, day: 24)
    static let lernen = "LERNEN"

    /// `testEdits`: Testgruppe, Testkategorie and Lernen's 25,00 / -40,00 in October 2026.
    static func budget(testEdits: Bool = false) throws -> Budget {
        var layout: [(id: String, name: String, subs: [(id: String, name: String)])] = [
            ("GEWINN", "Gewinn", [("AUSZAHLUNG", "Auszahlung")]),
            (
                "KRAM", "Kram",
                [
                    ("BUERO", "Bürogegenstände"), ("SOFTWARE", "Software"), (lernen, "Lernen"),
                    ("PLATTEN", "Festplatten"),
                ]
            ),
            (
                "REGEL", "Regelmäßige Ausgaben",
                [
                    ("ARQ", "Arq Backup"), ("FASTMAIL", "Fastmail"), ("KONTIST", "Kontist"), ("NEXTDNS", "NextDNS"),
                    ("LEXOFFICE", "Lexoffice"), ("HETZNER", "Hetzner"),
                ] + (testEdits ? [("TEST", "Testkategorie")] : [])
            ),
            (
                "RUECKLAGEN", "Rücklagen",
                [("BUFFER", "Buffer"), ("EST", "Einkommensstteuer 23"), ("UST", "Umsatzsteuer 23")]
            ),
        ]
        if testEdits { layout.insert(("TESTGRUPPE", "Testgruppe", []), at: 0) }
        let masters = layout.enumerated().map { index, master in
            CategoryGroup(
                id: master.id, name: master.name, position: index,
                categories: master.subs.enumerated().map { subIndex, sub in
                    Category(id: sub.id, categoryGroupId: master.id, name: sub.name, position: subIndex)
                })
        }
        var budget = Budget(
            budgetName: "Business",
            categoryGroups: [DefaultCategories.internalGroup()] + masters)
        budget.budgetMetaData.budgetType = .business
        try budget.apply(
            .addAccount(
                NewAccount(
                    id: "KONTIST-ACCOUNT", name: "Kontist", kind: .checking, startingBalance: 0,
                    startDate: date("2023-05-01"))))
        let monthly: [(String, Decimal)] = [
            ("BUERO", 10), ("SOFTWARE", 10), ("ARQ", 4.67), ("FASTMAIL", 5.89), ("KONTIST", 10.71), ("NEXTDNS", 1.54),
            ("LEXOFFICE", 20.11), ("HETZNER", 6), ("BUFFER", -68.92),
        ]
        var budgets: [(String, [(String, Decimal)])] = [
            (
                "2023-05-01",
                [
                    ("AUSZAHLUNG", 518.01), ("BUERO", 10), ("SOFTWARE", 10), ("ARQ", 5.68), ("FASTMAIL", 11.79),
                    ("KONTIST", 10.71), ("NEXTDNS", 4.62), ("LEXOFFICE", 40.22), ("HETZNER", 12), ("BUFFER", 321.36),
                    ("EST", -614), ("UST", -357.04),
                ]
            ),
            (
                "2023-06-01",
                [
                    ("AUSZAHLUNG", 1154.84), ("BUERO", 10), ("SOFTWARE", 10), (lernen, 15.99), ("ARQ", 55.89),
                    ("FASTMAIL", 5.89), ("KONTIST", 10.71), ("NEXTDNS", 1.54), ("HETZNER", 6), ("BUFFER", -80.34),
                ]
            ),
            (
                "2023-07-01",
                [
                    ("AUSZAHLUNG", 4136.81), ("BUERO", 10), ("SOFTWARE", 10), ("ARQ", 4.67), ("FASTMAIL", 5.89),
                    ("KONTIST", 10.71), ("NEXTDNS", 1.54), ("LEXOFFICE", 20.11), ("HETZNER", 6), ("BUFFER", -34.26),
                    ("UST", -57),
                ]
            ),
            ("2023-08-01", [("AUSZAHLUNG", 2490.12)] + monthly),
            ("2023-09-01", monthly),
            ("2023-10-01", monthly),
            ("2026-10-01", [("PLATTEN", 100)]),
        ]
        if testEdits { budgets.append(("2026-10-01", [(lernen, 25)])) }
        for (month, amounts) in budgets {
            for (category, amount) in amounts {
                try budget.apply(.setAssigned(month: date(month), categoryId: category, amount: amount))
            }
        }
        let income = budget.readyToAssignCategoryId
        var activity: [(String, Decimal, String)] = [
            ("2023-05-08", -11.76, "SOFTWARE"), ("2023-05-12", -5.45, "ARQ"),
            ("2023-05-20", -10.40, income),
            ("2023-06-02", 1154.84, income), ("2023-06-05", -1672.85, "AUSZAHLUNG"),
            ("2023-06-07", -15.99, lernen), ("2023-06-09", -56.12, "ARQ"), ("2023-06-11", -11.12, "KONTIST"),
            ("2023-06-13", -20.11, "LEXOFFICE"), ("2023-06-15", 427.13, "EST"), ("2023-06-15", 300.57, "UST"),
            ("2023-07-02", 6624.02, income), ("2023-07-05", -4136.81, "AUSZAHLUNG"),
            ("2023-07-06", -5.83, "SOFTWARE"), ("2023-07-08", -11.84, "KONTIST"), ("2023-07-10", -20.11, "LEXOFFICE"),
            ("2023-07-12", -12.97, "HETZNER"), ("2023-07-15", 2449.97, "EST"), ("2023-07-15", 1724.06, "UST"),
        ]
        if testEdits { activity.append(("2026-10-24", -40, lernen)) }
        for (day, amount, category) in activity {
            let transaction = Transaction(
                accountId: "KONTIST-ACCOUNT", date: date(day), categoryId: category, amount: amount)
            try budget.apply(.addTransaction(transaction, payeeName: amount > 0 ? "Finanzamt" : "Kontist"))
        }
        return budget
    }

    private static func date(_ text: String) -> DateWithoutTime {
        DateWithoutTime(string: text)!
    }
}

@MainActor
struct BudgetHarness {
    enum State: String, CaseIterable {
        case screen, edit
        case quickBudget = "quick-budget"
        case calculator
        case expandedHeader = "expanded-header"
        case collapsedAll = "collapsed-all"
        case drag, hover, uncategorized
        case quickBudgetMenu = "quick-budget-menu"
        case quickBudgetConfirm = "quick-budget-confirm"
        case addMaster = "add-master"
        case addSub = "add-sub"
        case editCategory = "edit-category"
        case editMaster = "edit-master"
        case renameError = "rename-error"
        case deleteCategory = "delete-category"
        case summary
        case incomeSummary = "income-summary"
        case uncategorizedSummary = "uncategorized-summary"
        case outflowHelp = "outflow-help"
        case cover, move
        case accountView = "account-view"
        case targets, target
        case targetEditor = "target-editor"
        case assign
    }

    let model: AppModel
    let edit: EditHarness

    private var budget: BudgetViewModel { model.budget }

    func run(_ state: State, month: DateWithoutTime?) throws {
        edit.settle()
        if let month { budget.select(month) }
        edit.settle()
        let lernen = BudgetCellID(month: budget.firstMonth, categoryId: BudgetReference.lernen)
        switch state {
        case .screen:
            break
        case .edit:
            budget.beginEdit(lernen)
        case .quickBudget:
            budget.beginEdit(lernen)
            edit.settle()
            edit.send(String(UnicodeScalar(NSF2FunctionKey)!), keyCode: UInt16(kVK_F2))
        case .calculator:
            budget.beginEdit(lernen)
            edit.settle()
            edit.type("+")
        case .expandedHeader:
            budget.toggleHeaderDetails()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        case .collapsedAll:
            budget.collapseAllClicked()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        case .drag:
            let rows = budget.groups.visibleRows
            guard let from = rows.firstIndex(where: { $0.id == BudgetReference.lernen }),
                let to = rows.firstIndex(where: { $0.id == "HETZNER" })
            else { throw SnapshotError.render }
            let start = CGPoint(x: 40, y: CGFloat(from) * BudgetMetrics.rowHeight + 11)
            budget.dragPressed(rowId: BudgetReference.lernen, at: start)
            budget.dragMoved(to: CGPoint(x: 65, y: CGFloat(to) * BudgetMetrics.rowHeight + 17))
        case .hover:
            budget.rowHovered("KRAM", true)
            budget.assignedCellHovered(lernen, true)
        case .uncategorized:
            try addUncategorizedOutflow()
        case .targets:
            try addTargets()
        default:
            try openPopup(state, month: budget.firstMonth)
        }
        edit.settle()
    }

    private func addUncategorizedOutflow() throws {
        let transaction = Transaction(
            accountId: "KONTIST-ACCOUNT", date: BudgetReference.today, categoryId: nil, amount: -7)
        try model.store.perform(.addTransaction(transaction, payeeName: "Kiosk"))
    }

    /// Software underfunded, Festplatten funded, Bürogegenstände snoozed and Lernen saving by a date in October 2026.
    private func addTargets() throws {
        let october = BudgetReference.today.firstOfMonth
        let targets: [(String, Target)] = [
            ("SOFTWARE", .monthly(10)), ("PLATTEN", .monthly(100)), ("BUERO", .monthly(10)),
            (BudgetReference.lernen, .byDate(240, due: DateWithoutTime(year: 2027, month: 6, day: 30))),
        ]
        for (category, target) in targets {
            try model.store.perform(.setTarget(month: october, categoryId: category, target: target))
        }
        try model.store.perform(.setTargetSnoozed(month: october, categoryId: "BUERO", true))
        try model.store.perform(.setAssigned(month: october, categoryId: BudgetReference.lernen, amount: 20))
    }

    private func overspendLernen() throws {
        let transaction = Transaction(
            accountId: "KONTIST-ACCOUNT", date: BudgetReference.today, categoryId: BudgetReference.lernen, amount: -40)
        try model.store.perform(.addTransaction(transaction, payeeName: "Kiosk"))
    }

    private func openPopup(_ state: State, month: DateWithoutTime) throws {
        let lernen = BudgetReference.lernen
        let callouts = budget.callouts
        switch state {
        case .quickBudgetMenu:
            budget.present(.monthQuickBudget(month: month))
        case .quickBudgetConfirm:
            callouts.quickBudgetChosen(.assignedLastMonth, month: month)
        case .addMaster:
            budget.addMasterCategoryClicked()
        case .addSub:
            let master = budget.groups.first { $0.header.kind == .master && $0.subs.isEmpty }?.id ?? "GEWINN"
            budget.rowHovered(master, true)
            budget.addSubCategoryClicked(masterId: master)
        case .editCategory, .renameError, .deleteCategory:
            budget.rowHovered(lernen, true)
            budget.present(.editCategory(categoryId: lernen))
            edit.settle()
            if state == .renameError {
                callouts.categoryName = "Software"
                callouts.categoryDone()
            } else if state == .deleteCategory {
                callouts.deleteCategoryClicked()
            }
        case .editMaster:
            budget.rowHovered("KRAM", true)
            budget.present(.editCategory(categoryId: "KRAM"))
        case .summary, .accountView:
            budget.present(.outflowSummary(month: month, source: .category(lernen)))
            edit.settle()
            if state == .accountView { callouts.showInAccountViewClicked() }
        case .incomeSummary:
            budget.present(.incomeSummary(month: month))
        case .uncategorizedSummary:
            try addUncategorizedOutflow()
            edit.settle()
            budget.present(.outflowSummary(month: month, source: .masterCategory(EntityID.uncategorizedMasterCategory)))
        case .outflowHelp:
            budget.present(.outflowHelp(month: month, categoryId: lernen))
        case .cover:
            try overspendLernen()
            edit.settle()
            budget.present(.available(month: BudgetReference.today.firstOfMonth, categoryId: lernen))
        case .move:
            budget.present(.available(month: BudgetReference.today.firstOfMonth, categoryId: "PLATTEN"))
        case .target, .targetEditor:
            try addTargets()
            budget.rowHovered(lernen, true)
            budget.present(.editCategory(categoryId: lernen, month: BudgetReference.today.firstOfMonth))
            edit.settle()
            if state == .targetEditor {
                callouts.editTargetClicked()
                callouts.targetRepeatsYearly = true
            }
        case .assign:
            try addTargets()
            edit.settle()
            budget.present(.assignToCategory(month: BudgetReference.today.firstOfMonth))
        case .screen, .edit, .quickBudget, .calculator, .expandedHeader, .collapsedAll, .drag, .hover, .uncategorized,
            .targets:
            break
        }
    }

    private func require<T>(_ value: T?) throws -> T {
        guard let value else { throw SnapshotError.render }
        return value
    }
}

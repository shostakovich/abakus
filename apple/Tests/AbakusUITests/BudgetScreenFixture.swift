import AbakusCore
import CoreGraphics
import Foundation

@testable import AbakusUI

/// A German budget on 24.10.2026: Alltag (Lebensmittel, Kleidung), Sparen (Notgroschen), Freizeit (Kino).
struct BudgetScreenFixture {
    static let today = day("2026-10-24")
    static let panel = CGSize(width: 1076, height: 783)

    static let giro = "GIRO"
    static let alltag = "ALLTAG"
    static let sparen = "SPAREN"
    static let freizeit = "FREIZEIT"
    static let lebensmittel = "LEBENSMITTEL"
    static let kleidung = "KLEIDUNG"
    static let notgroschen = "NOTGROSCHEN"
    static let kino = "KINO"
    static let readyToAssign = "READY"

    var budget: Budget

    init() {
        let layout: [(String, String, [(String, String)])] = [
            (Self.alltag, "Alltag", [(Self.lebensmittel, "Lebensmittel"), (Self.kleidung, "Kleidung")]),
            (Self.sparen, "Sparen", [(Self.notgroschen, "Notgroschen")]),
            (Self.freizeit, "Freizeit", [(Self.kino, "Kino")]),
        ]
        let masters = layout.enumerated().map { index, master in
            CategoryGroup(
                id: master.0, name: master.1, position: index,
                categories: master.2.enumerated().map { subIndex, sub in
                    Category(id: sub.0, categoryGroupId: master.0, name: sub.1, position: subIndex)
                })
        }
        budget = Budget(
            budgetName: "Budget",
            categoryGroups: [DefaultCategories.internalGroup(id: "INTERNAL", readyToAssignId: Self.readyToAssign)]
                + masters)
        try! budget.apply(
            .addAccount(
                NewAccount(
                    id: Self.giro, name: "Giro", kind: .checking, startingBalance: 0,
                    startDate: day("2026-08-01"))))
    }

    mutating func budget(_ amount: Decimal, _ category: String, in month: String) {
        try! budget.apply(.setAssigned(month: day(month), categoryId: category, amount: amount))
    }

    mutating func spend(_ amount: Decimal, _ category: String?, on date: String) {
        let transaction = Transaction(accountId: Self.giro, date: day(date), categoryId: category, amount: -amount)
        try! budget.apply(.addTransaction(transaction, payeeName: "Laden"))
    }

    @MainActor
    func model(
        appliesCommands: Bool = true, storage: MemorySettingsStorage? = nil, panel: CGSize = Self.panel
    ) -> (model: BudgetViewModel, store: SpyBudgetStore) {
        let store = SpyBudgetStore(budget: budget, today: Self.today, appliesCommands: appliesCommands)
        let settings = BudgetViewSettings(
            budget: storage.map { BudgetSettings(storage: $0, budgetKey: "Budget") }, app: storage)
        let model = BudgetViewModel(
            store: store, navigation: NavigationState(selection: .budget), dialogs: DialogStack(), settings: settings)
        model.panelSize = panel
        return (model, store)
    }
}

extension BudgetViewModel {
    func cell(_ category: String, _ month: String = "2026-10-01") -> BudgetCellID {
        BudgetCellID(month: day(month), categoryId: category)
    }
}

extension SpyBudgetStore {
    var assignedCommands: [BudgetCommand] {
        commands.filter {
            if case .setAssigned = $0 { return true }
            return false
        }
    }
}

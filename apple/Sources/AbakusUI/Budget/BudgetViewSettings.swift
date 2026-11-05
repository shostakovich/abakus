import AbakusCore
import CoreGraphics
import Foundation

@MainActor
final class BudgetViewSettings {
    static let lastSelectedMonthKey = "lastSelectedMonth"
    static let lastTabShownKey = "lastTabShown"
    static let headerExpandedKey = "budgetHeaderExpanded"
    static let budgetTab = "Budget"
    static let accountsTab = "Accounts"

    private let budget: BudgetSettings?
    private let app: (any SettingsStorage)?
    private var memory: [String: String] = [:]

    init(budget: BudgetSettings?, app: (any SettingsStorage)?) {
        self.budget = budget
        self.app = app
    }

    var lastSelectedMonth: DateWithoutTime? {
        get { budgetValue(Self.lastSelectedMonthKey).flatMap { DateWithoutTime(string: $0 + "-01") } }
        set { setBudgetValue(newValue?.monthKey, Self.lastSelectedMonthKey) }
    }

    var opensOnBudget: Bool {
        get { budgetValue(Self.lastTabShownKey) == Self.budgetTab }
        set { setBudgetValue(newValue ? Self.budgetTab : Self.accountsTab, Self.lastTabShownKey) }
    }

    var isHeaderExpanded: Bool {
        get { (app?.string(forKey: Self.headerExpandedKey) ?? memory[Self.headerExpandedKey]) == "true" }
        set {
            let value = newValue ? "true" : "false"
            if let app {
                app.set(value, forKey: Self.headerExpandedKey)
            } else {
                memory[Self.headerExpandedKey] = value
            }
        }
    }

    private func budgetValue(_ name: String) -> String? {
        budget.map { $0.string(forKey: name) } ?? memory[name]
    }

    private func setBudgetValue(_ value: String?, _ name: String) {
        guard let budget else {
            memory[name] = value
            return
        }
        budget.set(value ?? "", forKey: name)
    }
}

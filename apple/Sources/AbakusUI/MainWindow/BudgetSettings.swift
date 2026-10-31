import AbakusCore
import Foundation

public protocol SettingsStorage: AnyObject {
    func string(forKey defaultName: String) -> String?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: SettingsStorage {}

/// Settings of one budget on this machine, keyed by its database.
@MainActor
struct BudgetSettings {
    let storage: any SettingsStorage
    let budgetKey: String

    init(storage: any SettingsStorage, store: BudgetStore) {
        self.init(storage: storage, budgetKey: store.databaseURL?.path ?? store.budget.budgetName)
    }

    init(storage: any SettingsStorage, budgetKey: String) {
        self.storage = storage
        self.budgetKey = budgetKey
    }

    func string(forKey name: String) -> String? {
        storage.string(forKey: key(name))
    }

    func set(_ value: String, forKey name: String) {
        storage.set(value, forKey: key(name))
    }

    private func key(_ name: String) -> String {
        name + "|" + budgetKey
    }
}

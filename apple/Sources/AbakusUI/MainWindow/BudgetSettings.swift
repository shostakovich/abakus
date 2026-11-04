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
        self.init(storage: storage, budgetKey: store.databaseURL.map(Self.budgetKey) ?? store.budget.budgetName)
    }

    /// An iOS app's container moves with every install, so the key starts inside it.
    private static func budgetKey(_ url: URL) -> String {
        #if os(iOS)
            KeychainTokenStore.account(forDatabaseAt: url, inContainer: URL(fileURLWithPath: NSHomeDirectory()))
        #else
            url.path
        #endif
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

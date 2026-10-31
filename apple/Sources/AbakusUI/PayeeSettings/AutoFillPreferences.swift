import AbakusCore
import Foundation

/// Application preferences, not stored in the budget.
@MainActor
enum AutoFillPreferences {
    static let categoryKey = "shouldAutofillCategory"
    static let memoKey = "shouldAutofillMemo"
    static let amountKey = "shouldAutofillAmount"

    static func load(from storage: (any SettingsStorage)?) -> AutoFillSettings {
        let defaults = AutoFillSettings()
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            storage?.string(forKey: key).map { $0 == "true" } ?? fallback
        }
        return AutoFillSettings(
            category: flag(categoryKey, defaults.category), memo: flag(memoKey, defaults.memo),
            amount: flag(amountKey, defaults.amount))
    }

    static func save(_ settings: AutoFillSettings, to storage: (any SettingsStorage)?) {
        storage?.set(String(settings.category), forKey: categoryKey)
        storage?.set(String(settings.memo), forKey: memoKey)
        storage?.set(String(settings.amount), forKey: amountKey)
    }
}

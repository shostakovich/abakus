import AbakusCore
import Foundation

extension AppModel {
    /// The named payee, else the one used last; one dialog at a time.
    public func openPayeeSettings(payeeName: String?) {
        guard payeeSettings == nil, !register.isBlockedByModal else { return }
        if let id = payeeName.flatMap({ store.budget.payee(named: $0, includingTransfers: true)?.id }) {
            lastUsedPayeeId = id
        }
        let model = PayeeSettingsModel(
            store: store, initialPayeeId: lastUsedPayeeId, autoFill: register.autoFillSettings, dialogs: dialogs)
        model.onAutoFillChanged = { [weak self] settings in
            guard let self else { return }
            register.autoFillSettings = settings
            AutoFillPreferences.save(settings, to: preferences)
        }
        model.onShowTransactions = { [weak self] name, scheduled in
            self?.register.showPayeeTransactions(name, showingScheduled: scheduled)
        }
        model.onClose = { [weak self] lastUsed in
            guard let self else { return }
            if let lastUsed { lastUsedPayeeId = lastUsed }
            payeeSettings = nil
            register.endEditsOvertakenByChanges()
        }
        payeeSettings = model
    }
}

import Foundation

/// Touch screens act on the scheduled transactions a context menu or a swipe names.
extension RegisterScheduler {
    /// The menu of the rows named, not of the grid's selection; their own account is no move target.
    public func actionsMenu(for ids: Set<String>) -> [RegisterMenuItem] {
        let budget = store.budget
        let accounts = Set(ids.compactMap { budget.scheduledTransaction(withId: $0)?.accountId })
        guard !accounts.isEmpty else { return [] }
        let targets = budget.moveTargets(excluding: accounts.count == 1 ? accounts.first : register.accountKey)
        return [
            .action(Self.enterTitle, .enterScheduledNow, enabled: canEnter(ids), systemImage: "checkmark"),
            .action(Self.skipTitle, .skipScheduled, systemImage: "forward"),
            .separator(1),
            .action(Self.deleteTitle.touchLabel, .deleteScheduled, systemImage: "trash"),
            .separator(2),
            RegisterMenuItem(
                id: "move", title: Self.moveTitle,
                kind: .submenu(targets.map { .action($0.name, .moveScheduled(accountId: $0.id)) }),
                isEnabled: !targets.isEmpty, systemImage: "arrow.right.square"),
        ]
    }

    public func performMenuAction(_ action: RegisterMenuAction, on ids: Set<String>) {
        let order = scheduledIds
        grid.updateSelection { selection in
            selection.clear()
            for id in order where ids.contains(id) { selection.toggle(id) }
        }
        register.performMenuAction(action)
    }
}

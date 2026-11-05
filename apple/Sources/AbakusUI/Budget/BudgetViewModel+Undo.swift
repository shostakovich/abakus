import AbakusCore
import Foundation
import SwiftUI

/// Covering, filling and a target's Zuweisen say what they moved and offer to move it back.
public struct BudgetUndoNotice: Identifiable, Equatable, Sendable {
    public static let lifetime: Duration = .seconds(5)
    public static let undoTitle = "Rückgängig"

    public let id = UUID()
    public let message: String
    let month: DateWithoutTime
    let changes: [AssignedChange]
    let actionName: String
    let budgetAfter: Budget
    let token: BudgetUndoToken

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// The target the window's UndoManager keeps an action under, so the notice can take it off again.
final class BudgetUndoToken: Sendable {}

/// The UndoManager's action, valid only while the budget is as that action left it.
struct BudgetUndoRegistration {
    let token: BudgetUndoToken
    let budgetAfter: Budget
}

extension BudgetViewModel {
    /// Only while the budget is as the action left it.
    public var undoNotice: BudgetUndoNotice? {
        guard let notice = storedUndoNotice, notice.budgetAfter == store.budget else { return nil }
        return notice
    }

    /// Runs as long as the view showing the notice; however it ends, the notice never comes back.
    public func undoNoticeShown(_ notice: BudgetUndoNotice) async {
        AccessibilityNotification.Announcement(notice.message).post()
        try? await Task.sleep(for: BudgetUndoNotice.lifetime)
        undoNoticeExpired(notice.id)
    }

    public func undoNoticeExpired(_ id: UUID) {
        if storedUndoNotice?.id == id { storedUndoNotice = nil }
    }

    public func undoNoticeClicked() {
        guard let notice = undoNotice else { return }
        storedUndoNotice = nil
        dropUndo()
        perform(.changeAssigned(month: notice.month, notice.changes.map(\.negated)))
    }

    /// The category's name without its emoji, as a sentence names it.
    func plainName(of categoryId: String) -> String {
        let name = store.budget.categoryName(categoryId)
        return name.leadingEmoji?.name ?? name
    }

    func performUndoable(
        _ command: BudgetCommand, month: DateWithoutTime, actionName: String, message: (Decimal) -> String
    ) {
        commitEdit()
        let before = assignedAmounts(in: month)
        perform(command)
        let after = assignedAmounts(in: month)
        let changes = before.indices.compactMap { index -> AssignedChange? in
            let change = after[index].amount - before[index].amount
            return change == 0 ? nil : AssignedChange(categoryId: before[index].categoryId, amount: change)
        }
        guard !changes.isEmpty else { return }
        let token = BudgetUndoToken()
        storedUndoNotice = BudgetUndoNotice(
            message: message(Amount.sum(changes.map(\.amount).filter { $0 > 0 })), month: month, changes: changes,
            actionName: actionName, budgetAfter: store.budget, token: token)
        registerUndo(changes.map(\.negated), month: month, actionName: actionName, token: token)
    }

    private func assignedAmounts(in month: DateWithoutTime) -> [AssignedChange] {
        let budget = store.budget
        return budget.budgetCategoryGroups.flatMap(\.categories).map {
            AssignedChange(categoryId: $0.id, amount: budget.assigned(in: month, categoryId: $0.id))
        }
    }

    /// Any later write takes the action off the UndoManager, so ⌘Z never moves money by a stale difference.
    func dropStaleUndo() {
        guard let undoRegistration, undoRegistration.budgetAfter != store.budget else { return }
        dropUndo()
    }

    private func dropUndo() {
        guard let undoRegistration else { return }
        self.undoRegistration = nil
        undoManager?.removeAllActions(withTarget: undoRegistration.token)
    }

    /// Undoing registers the way back, which the UndoManager keeps as its redo.
    private func registerUndo(
        _ changes: [AssignedChange], month: DateWithoutTime, actionName: String, token: BudgetUndoToken
    ) {
        guard let undoManager else { return }
        undoRegistration = BudgetUndoRegistration(token: token, budgetAfter: store.budget)
        // The UndoManager does not retain its targets, so the action keeps its token alive.
        undoManager.registerUndo(withTarget: token) { [weak self, token] _ in
            guard let self, let registration = undoRegistration, registration.token === token,
                registration.budgetAfter == store.budget
            else { return }
            undoRegistration = nil
            storedUndoNotice = nil
            perform(.changeAssigned(month: month, changes))
            registerUndo(changes.map(\.negated), month: month, actionName: actionName, token: token)
        }
        undoManager.setActionName(actionName)
        watchForOtherWrites(token)
    }

    /// Writes from elsewhere, such as the register or sync, end the action too.
    private func watchForOtherWrites(_ token: BudgetUndoToken) {
        withObservationTracking {
            _ = store.budget
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.budgetWritten(since: token) }
        }
    }

    private func budgetWritten(since token: BudgetUndoToken) {
        guard undoRegistration?.token === token else { return }
        dropStaleUndo()
        if undoRegistration?.token === token { watchForOtherWrites(token) }
    }
}

import AbakusCore
import Foundation
import Observation

@MainActor
@Observable
public final class RegisterNotifierController {
    unowned let register: RegisterViewModel
    private var storedUndoSlot: RegisterUndoSlot?

    init(register: RegisterViewModel) {
        self.register = register
    }

    public var undoSlot: RegisterUndoSlot? {
        guard let slot = storedUndoSlot, slot.budgetAfter == register.store.budget else { return nil }
        return slot
    }

    func offerUndo(message: String, restore: RegisterUndoSlot.Restore, reselect: [String]) {
        storedUndoSlot = RegisterUndoSlot(
            message: message, restore: restore, reselect: reselect, budgetAfter: register.store.budget)
    }

    /// The open notices as chips, each but the error a click away from the view that lists them, which hides it;
    /// undo last.
    public var list: [RegisterNotifier] {
        let counts = register.derived.notifierCounts
        var notifiers: [RegisterNotifier] = []
        // A transfer with a category has no view of its own, and a reconciliation keeps Alle Buchungen.
        let leadsToView = !register.isReconciling
        func add(_ kind: RegisterNotifier.Kind, _ count: Int, one: String, many: String, tooltip: String) {
            guard count > 0 else { return }
            notifiers.append(
                RegisterNotifier(
                    kind: kind, text: count == 1 ? "1 \(one)" : "\(count) \(many)", tooltip: tooltip,
                    isClickable: kind != .error && leadsToView))
        }
        let errors = counts.errors
        add(
            .error, errors, one: "Umbuchung mit Kategorie", many: "Umbuchungen mit Kategorie",
            tooltip: errors == 1
                ? "1 Umbuchung zwischen Budgetkonten hat eine Kategorie"
                : "\(errors) Umbuchungen zwischen Budgetkonten haben eine Kategorie")
        let warnings = register.filter == .needsCategory ? 0 : counts.needsCategory
        add(
            .warning, warnings, one: "braucht eine Kategorie", many: "brauchen eine Kategorie",
            tooltip: warnings == 1
                ? "1 Buchung braucht eine Kategorie" : "\(warnings) Buchungen brauchen eine Kategorie")
        let reminders = register.filter == .unapproved ? 0 : counts.unapproved
        add(
            .reminder, reminders, one: "bestätigen", many: "bestätigen",
            tooltip: reminders == 1 ? "1 Buchung ist zu bestätigen" : "\(reminders) Buchungen sind zu bestätigen")
        if let undo = undoSlot {
            notifiers.append(RegisterNotifier(kind: .undo, text: undo.message, link: "Widerrufen"))
        }
        return notifiers
    }

    public func clicked(_ kind: RegisterNotifier.Kind) {
        guard !register.grid.clickedOutsideEditor() else { return }
        switch kind {
        case .error: break
        case .warning: show(.needsCategory)
        case .reminder: show(.unapproved)
        case .undo: undoClicked()
        }
    }

    private func show(_ filter: RegisterFilter) {
        guard !register.isReconciling else { return }
        register.search.cancel()
        register.setFilter(filter)
    }

    public func undoClicked() {
        guard let slot = undoSlot else { return }
        storedUndoSlot = nil
        let command: BudgetCommand =
            switch slot.restore {
            case .deleted(let transactions, let payees): .restoreTransactions(transactions, payees: payees)
            case .moved(let moved), .movedSchedules(let moved): .restoreMovedTransactions(moved)
            }
        guard register.perform(command) else { return }
        if case .movedSchedules = slot.restore {
            register.scheduler.reselect(slot.reselect)
            return
        }
        let visible = Set(register.transactionIds)
        register.updateSelection { selection in
            for id in slot.reselect where visible.contains(id) && !selection.contains(id) { selection.toggle(id) }
        }
    }

    public func dismissUndo() {
        storedUndoSlot = nil
    }
}

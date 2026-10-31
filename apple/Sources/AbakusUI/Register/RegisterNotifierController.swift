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

    /// Only the first visible notifier gets its full text and link; the undo notifier always shows its message.
    public var list: [RegisterNotifier] {
        let counts = register.derived.notifierCounts
        var notifiers: [RegisterNotifier] = []
        func add(_ kind: RegisterNotifier.Kind, full: String, short: String) {
            let isFirst = notifiers.isEmpty
            notifiers.append(RegisterNotifier(kind: kind, text: isFirst ? full : short, link: isFirst ? "Zeigen" : nil))
        }
        let errors = counts.errors
        if errors > 0 {
            let text =
                errors == 1
                ? "1 Umbuchung zwischen Budgetkonten hat eine Kategorie"
                : "\(errors) Umbuchungen zwischen Budgetkonten haben eine Kategorie"
            add(.error, full: text, short: "")
        }
        let warnings = counts.needsCategory
        if warnings > 0 {
            add(
                .warning,
                full: warnings == 1
                    ? "1 Buchung braucht eine Kategorie" : "\(warnings) Buchungen brauchen eine Kategorie",
                short: warnings == 1 ? "1 Warnung" : "\(warnings) Warnungen")
        }
        let reminders = counts.forReview
        if reminders > 0 {
            add(
                .reminder,
                full: reminders == 1
                    ? "1 Buchung ist zu bestätigen" : "\(reminders) Buchungen sind zu bestätigen",
                short: reminders == 1 ? "1 Erinnerung" : "\(reminders) Erinnerungen")
        }
        if let undo = undoSlot {
            notifiers.append(RegisterNotifier(kind: .undo, text: undo.message, link: "Widerrufen"))
        }
        return notifiers
    }

    public func clicked(_ kind: RegisterNotifier.Kind) {
        guard !register.grid.clickedOutsideEditor() else { return }
        switch kind {
        case .error: register.search.run("Ist: Fehler")
        case .warning: register.search.run("Ist: Nicht kategorisiert")
        case .reminder: register.search.run("Ist: Erinnerung")
        case .undo: undoClicked()
        }
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

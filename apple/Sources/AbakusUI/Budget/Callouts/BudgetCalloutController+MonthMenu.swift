import AbakusCore
import Foundation

enum ResetAssignedChoice: Hashable, Sendable {
    case cancel, reset
}

extension BudgetCalloutController {
    static let fillUnderfundedTitle = "Ziele füllen"
    static let resetAssignedTitle = "Zurücksetzen …"

    /// Verteilen: an entry the month has nothing for is dimmed and says why.
    public func monthMenu(month date: DateWithoutTime) -> [RegisterMenuItem] {
        let sheet = budget.sheet
        let month = sheet.month(date)
        let fill = Amount.sum(sheet.underfundedFills(in: date).map(\.amount))
        let fillSubtitle =
            if fill > 0 { formatter.currency(fill) } else if sheet.underfunded(in: date) == 0 {
                "Nichts unterfinanziert"
            } else { "Nichts zu verteilen" }
        let hasAssignments =
            month.map { month in
                sheet.categoryGroups.flatMap(\.categories).contains { month.category($0.id)?.assigned != 0 }
            }
            ?? false
        return [
            .action(
                Self.fillUnderfundedTitle, .fillUnderfunded, enabled: fill > 0, systemImage: "target",
                subtitle: fillSubtitle),
            .action(
                Self.resetAssignedTitle, .resetAssigned, enabled: hasAssignments,
                systemImage: "arrow.counterclockwise",
                subtitle: hasAssignments
                    ? "Zuweisungen im \(formatter.shortMonthName(date.month))" : "Nichts zugewiesen",
                isDestructive: true),
        ]
    }

    public func monthMenuChosen(_ action: RegisterMenuAction, month: DateWithoutTime) {
        switch action {
        case .fillUnderfunded:
            budget.performUndoable(
                .fillUnderfunded(month: month, today: budget.today), month: month,
                actionName: Self.fillUnderfundedTitle
            ) { "Ziele mit \(self.formatter.currency($0)) gefüllt." }
        case .resetAssigned: confirmReset(month: month)
        default: break
        }
    }

    private func confirmReset(month: DateWithoutTime) {
        let dialog = TaskDialog<ResetAssignedChoice>(
            instruction: "Alle Zuweisungen im \(formatter.monthName(month.month)) zurücksetzen?",
            content: "Zu verteilen bekommt das Geld zurück.",
            buttons: [.init(.cancel, title: "Abbrechen"), .init(.reset, title: "Zurücksetzen", isDefault: true)],
            dismissal: .cancel)
        dialogs.ask(dialog) { [weak self] answer in
            guard let self, answer.choice == .reset else { return }
            budget.perform(.resetAssigned(month: month))
        }
    }

    public func monthMenuClosed() {
        guard case .monthMenu = budget.presentedPopup else { return }
        budget.dismissPopup()
    }
}

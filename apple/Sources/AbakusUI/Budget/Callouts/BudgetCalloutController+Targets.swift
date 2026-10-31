import AbakusCore
import Foundation

public enum BudgetTargetCadence: Hashable, Sendable, CaseIterable {
    case monthly, byDate

    public var title: String {
        switch self {
        case .monthly: "Jeden Monat"
        case .byDate: "Bis zum Datum"
        }
    }
}

public enum BudgetTargetKind: Hashable, Sendable, CaseIterable {
    case setAside, refill

    public var title: String {
        switch self {
        case .setAside: "Weitere zurücklegen"
        case .refill: "Auffüllen bis"
        }
    }
}

/// The target editor in the category callout: what was typed, saved from the callout's month on.
public struct BudgetTargetForm: Hashable, Sendable {
    public var amount: String
    public var cadence: BudgetTargetCadence
    public var dueOn: DateWithoutTime
    public var repeatsYearly: Bool
    public var kind: BudgetTargetKind
    public let isNew: Bool
    public internal(set) var error: String?
    public internal(set) var focusRequest = 0
}

public struct BudgetTargetProgress: Hashable, Sendable {
    public let label: String
    public let value: Double
    public let mark: Double?

    public var percentText: String { "\(Int((value * 100).rounded())) %" }
}

/// The target as the category callout shows it in its month.
public struct BudgetTargetDisplay: Hashable, Sendable {
    public let head: String
    public let status: BudgetTargetStatus
    /// "Zuweisen" assigns what is still missing, as far as Zu verteilen reaches.
    public let assignLabel: String?
    public let progress: BudgetTargetProgress?
    public let isSnoozed: Bool

    public var snoozeTitle: String { isSnoozed ? "Fortsetzen" : "Pausieren" }
}

extension BudgetCalloutController {
    static let noTargetText = "Kein Ziel. Ein Ziel sagt dir, wie viel diese Kategorie jeden Monat braucht."

    public var targetMonthTitle: String {
        category.map { formatter.monthHeader($0.month) } ?? ""
    }

    private var targetFigures: BudgetCategoryFigures? {
        guard let form = category, form.hasTarget else { return nil }
        return budget.sheet.month(form.month)?.category(form.categoryId)
    }

    public var targetDisplay: BudgetTargetDisplay? {
        guard let form = category, let figures = targetFigures, let target = figures.target,
            let status = formatter.targetStatus(figures, month: form.month)
        else { return nil }
        let assigns = target.openNeed > 0 && figures.balance >= 0
        return BudgetTargetDisplay(
            head: formatter.targetHead(target.target), status: status,
            assignLabel: assigns ? "\(formatter.currency(target.underfunded)) zuweisen" : nil,
            progress: target.target.cadence == .byDate
                ? BudgetTargetProgress(
                    label: formatter.targetSavedLabel(target), value: target.progress, mark: target.mark) : nil,
            isSnoozed: target.isSnoozed)
    }

    public func editTargetClicked() {
        guard let form = category else { return }
        let target = store.budget.target(in: form.month, categoryId: form.categoryId)
        let dueOn =
            target?.nextDue(from: form.month) ?? DateWithoutTime(year: form.month.year, month: 12, day: 31)
        category?.target = BudgetTargetForm(
            amount: target.map { formatter.currencySimple($0.amount) } ?? "",
            cadence: target?.cadence == .byDate ? .byDate : .monthly, dueOn: dueOn,
            repeatsYearly: target?.repeatsYearly ?? false, kind: target?.setAside == false ? .refill : .setAside,
            isNew: target == nil)
    }

    public var targetAmount: String {
        get { category?.target?.amount ?? "" }
        set { changeTargetForm { $0.amount = newValue } }
    }

    public var targetCadence: BudgetTargetCadence {
        get { category?.target?.cadence ?? .monthly }
        set { changeTargetForm { $0.cadence = newValue } }
    }

    public var targetDueOn: DateWithoutTime {
        get { category?.target?.dueOn ?? budget.today }
        set { changeTargetForm { $0.dueOn = newValue } }
    }

    public var targetRepeatsYearly: Bool {
        get { category?.target?.repeatsYearly ?? false }
        set { changeTargetForm { $0.repeatsYearly = newValue } }
    }

    public var targetKind: BudgetTargetKind {
        get { category?.target?.kind ?? .setAside }
        set { changeTargetForm { $0.kind = newValue } }
    }

    private func changeTargetForm(_ change: (inout BudgetTargetForm) -> Void) {
        guard var target = category?.target else { return }
        change(&target)
        target.error = nil
        category?.target = target
    }

    public func targetCancelClicked() {
        category?.target = nil
    }

    /// Escape closes the target editor before the callout.
    func targetEscaped() -> Bool {
        guard category?.target != nil else { return false }
        targetCancelClicked()
        return true
    }

    public func targetSaveClicked() {
        saveOpenTarget()
    }

    /// False when the open target editor refused what was typed.
    @discardableResult
    func saveOpenTarget() -> Bool {
        guard let form = category, let editor = form.target else { return true }
        guard let version = targetVersion(editor, from: form.month) else { return false }
        setTarget(version)
        return true
    }

    private func targetVersion(_ editor: BudgetTargetForm, from month: DateWithoutTime) -> Target? {
        guard let amount = typedAmount(editor.amount) else { return targetError(Self.missingAmount) }
        let setAside = editor.kind == .setAside
        let version: Target =
            editor.cadence == .byDate
            ? .byDate(amount, due: editor.dueOn, repeatsYearly: editor.repeatsYearly, setAside: setAside)
            : .monthly(amount, setAside: setAside)
        do {
            return try Budget.validated(version, from: month.firstOfMonth)
        } catch {
            return targetError(error.localizedDescription)
        }
    }

    private func targetError(_ message: String) -> Target? {
        category?.target?.error = message
        category?.target?.focusRequest += 1
        return nil
    }

    public func deleteTargetClicked() {
        let dialog = TaskDialog<TargetDeleteChoice>(
            instruction: "Ziel löschen?", content: "Die Kategorie hat ab diesem Monat kein Ziel mehr.",
            buttons: [.init(.delete, title: "Ziel löschen"), .init(.cancel, title: "Abbrechen", isDefault: true)],
            dismissal: .cancel)
        dialogs.ask(dialog) { [weak self] answer in
            guard answer.choice == .delete else { return }
            self?.setTarget(.ended)
        }
    }

    private func setTarget(_ target: Target) {
        guard let form = category else { return }
        budget.perform(.setTarget(month: form.month, categoryId: form.categoryId, target: target))
        category?.target = nil
    }

    public func snoozeClicked() {
        guard let form = category, let target = targetFigures?.target else { return }
        budget.perform(.setTargetSnoozed(month: form.month, categoryId: form.categoryId, !target.isSnoozed))
    }

    public func assignTargetClicked() {
        guard let form = category, targetDisplay?.assignLabel != nil,
            case let amount = budget.sheet.assignSuggestion(categoryId: form.categoryId, in: form.month), amount > 0
        else { return }
        budget.perform(
            .moveAssigned(month: form.month, from: readyToAssignCategoryId, to: form.categoryId, amount: amount))
    }
}

enum TargetDeleteChoice: Hashable, Sendable {
    case delete, cancel
}

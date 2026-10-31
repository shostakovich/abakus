import Foundation

/// What Verfügbar marks besides overspending, which is red.
public enum BudgetAvailableMarker: Hashable, Sendable {
    case underfunded, funded, snoozed

    public var label: String {
        switch self {
        case .underfunded: "unterfinanziert"
        case .funded: "Ziel erreicht"
        case .snoozed: "Ziel pausiert"
        }
    }
}

public enum BudgetTargetState: Hashable, Sendable {
    case overspent, snoozed, underfunded, onTrack, met
}

public struct BudgetTargetStatus: Hashable, Sendable {
    public let state: BudgetTargetState
    public let text: String
}

extension BudgetCategoryFigures {
    /// An underfunded target shows only in a month being assigned.
    public func availableMarker(isBeingBudgeted: Bool) -> BudgetAvailableMarker? {
        guard let target, balance >= 0 else { return nil }
        if target.isSnoozed { return .snoozed }
        if target.openNeed > 0 { return isBeingBudgeted ? .underfunded : nil }
        return balance > 0 ? .funded : nil
    }
}

extension BudgetFormatter {
    /// Overspending wins over snoozing.
    public func targetStatus(_ figures: BudgetCategoryFigures, month: DateWithoutTime) -> BudgetTargetStatus? {
        guard let target = figures.target else { return nil }
        if figures.balance < 0 {
            return BudgetTargetStatus(state: .overspent, text: "Überzogen um \(currency(-figures.balance)).")
        }
        if target.isSnoozed {
            return BudgetTargetStatus(state: .snoozed, text: "Pausiert im \(monthName(month.month)).")
        }
        if target.underfunded > 0 {
            return BudgetTargetStatus(state: .underfunded, text: "Noch \(currency(target.underfunded)) diesen Monat.")
        }
        if let saved = target.saved, saved < target.target.amount {
            return BudgetTargetStatus(state: .onTrack, text: "Im Plan.")
        }
        return BudgetTargetStatus(state: .met, text: "Erfüllt.")
    }

    /// A repeating target by a date names its day without the year.
    public func targetHead(_ target: Target) -> String {
        let amount = currency(target.amount)
        switch target.cadence {
        case .monthly:
            return target.setAside
                ? "Jeden Monat weitere \(amount) zurücklegen" : "Jeden Monat auffüllen bis \(amount)"
        case .byDate:
            let due = target.dueOn.map { "\($0.day). \(monthName($0.month))" } ?? ""
            let by =
                target.repeatsYearly
                ? "Jedes Jahr bis zum \(due)" : "Bis zum \(due) \(target.dueOn.map { String($0.year) } ?? "")"
            return target.setAside ? "\(by) weitere \(amount) zurücklegen" : "\(by) auf \(amount) ansparen"
        case .ended:
            return ""
        }
    }

    public func targetSavedLabel(_ target: BudgetTargetFigures) -> String {
        "Angespart \(currencyNoSymbol(target.saved ?? 0)) von \(currency(target.target.amount))"
    }
}

extension BudgetTargetFigures {
    /// Where a target by a date should stand after this month, as a share of its amount.
    public var mark: Double? {
        guard target.cadence == .byDate, target.amount > 0 else { return nil }
        let share = NSDecimalNumber(decimal: ((saved ?? 0) + openNeed) / target.amount).doubleValue
        return min(1, share)
    }
}

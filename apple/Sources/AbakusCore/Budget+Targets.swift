import Foundation

extension Budget {
    /// Changing or ending a target stores a version in the month, so earlier months keep theirs.
    mutating func setTarget(_ target: Target, month: DateWithoutTime, categoryId: String) throws {
        try requireBudgetCategory(categoryId)
        let validated = try Self.validated(target, from: month.firstOfMonth)
        let version = TargetVersion(categoryId: categoryId, fromMonth: month, target: validated)
        targetVersions.removeAll { $0.id == version.id }
        if validated.isEnded && targetInEffect(before: month, categoryId: categoryId) == nil { return }
        targetVersions.append(version)
    }

    mutating func setTargetSnoozed(_ snoozed: Bool, month: DateWithoutTime, categoryId: String) throws {
        try requireBudgetCategory(categoryId)
        let snooze = TargetSnooze(categoryId: categoryId, month: month)
        targetSnoozes.removeAll { $0.id == snooze.id }
        if snoozed { targetSnoozes.append(snooze) }
    }

    public func isTargetSnoozed(in month: DateWithoutTime, categoryId: String) -> Bool {
        let id = EntityID.targetSnooze(categoryId: categoryId, month: month)
        return targetSnoozes.contains { $0.id == id }
    }

    /// The target in effect in the month, nil without one or after it was ended.
    public func target(in month: DateWithoutTime, categoryId: String) -> Target? {
        let latest = targetVersions.filter { $0.categoryId == categoryId && $0.fromMonth <= month.firstOfMonth }
            .max { $0.fromMonth < $1.fromMonth }
        guard let target = latest?.target, !target.isEnded else { return nil }
        return target
    }

    private func targetInEffect(before month: DateWithoutTime, categoryId: String) -> Target? {
        target(in: month.firstOfMonth.addingMonths(-1), categoryId: categoryId)
    }

    public static func validated(_ target: Target, from month: DateWithoutTime) throws -> Target {
        switch target.cadence {
        case .ended:
            return .ended
        case .monthly:
            try requirePositive(target.amount)
            return .monthly(target.amount, setAside: target.setAside)
        case .byDate:
            try requirePositive(target.amount)
            guard let due = target.dueOn, due >= month else { throw BudgetError.targetDueBeforeStart }
            return .byDate(target.amount, due: due, repeatsYearly: target.repeatsYearly, setAside: target.setAside)
        }
    }

    private static func requirePositive(_ amount: Decimal) throws {
        guard amount.isFinite else { throw BudgetError.amountNotFinite }
        guard amount > 0 else { throw BudgetError.targetAmountNotPositive }
    }
}

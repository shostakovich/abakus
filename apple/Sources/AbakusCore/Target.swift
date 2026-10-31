import Foundation

public enum TargetCadence: String, Codable, Hashable, Sendable {
    case monthly
    case byDate = "by_date"
    case ended = "none"
}

public struct Target: Hashable, Sendable {
    public var cadence: TargetCadence
    public var amount: Decimal
    public var dueOn: DateWithoutTime?
    public var repeatsYearly: Bool
    /// "Weitere zurücklegen" counts what is assigned; "Auffüllen bis" counts what is carried as well.
    public var setAside: Bool

    public init(
        cadence: TargetCadence, amount: Decimal = 0, dueOn: DateWithoutTime? = nil, repeatsYearly: Bool = false,
        setAside: Bool = true
    ) {
        self.cadence = cadence
        self.amount = Amount.round(amount)
        self.dueOn = dueOn
        self.repeatsYearly = repeatsYearly
        self.setAside = setAside
    }

    public static let ended = Target(cadence: .ended)

    public static func monthly(_ amount: Decimal, setAside: Bool = true) -> Target {
        Target(cadence: .monthly, amount: amount, setAside: setAside)
    }

    public static func byDate(
        _ amount: Decimal, due: DateWithoutTime, repeatsYearly: Bool = false, setAside: Bool = true
    ) -> Target {
        Target(cadence: .byDate, amount: amount, dueOn: due, repeatsYearly: repeatsYearly, setAside: setAside)
    }

    public var isEnded: Bool { cadence == .ended }

    /// A yearly due date moves on by whole years until it is not before `month`.
    public func nextDue(from month: DateWithoutTime) -> DateWithoutTime? {
        guard var due = dueOn else { return nil }
        guard repeatsYearly else { return due }
        while due < month.firstOfMonth { due = due.addingYears(1) }
        return due
    }
}

/// A category's target from `fromMonth` until its next version.
public struct TargetVersion: Hashable, Identifiable, Sendable {
    public var id: String
    public var categoryId: String
    public var fromMonth: DateWithoutTime
    public var cadence: TargetCadence
    public var amount: Decimal
    public var dueOn: DateWithoutTime?
    public var repeatsYearly: Bool
    public var setAside: Bool

    public init(categoryId: String, fromMonth: DateWithoutTime, target: Target) {
        id = EntityID.targetVersion(categoryId: categoryId, fromMonth: fromMonth)
        self.categoryId = categoryId
        self.fromMonth = fromMonth.firstOfMonth
        cadence = target.cadence
        amount = target.amount
        dueOn = target.dueOn
        repeatsYearly = target.repeatsYearly
        setAside = target.setAside
    }

    public var target: Target {
        Target(cadence: cadence, amount: amount, dueOn: dueOn, repeatsYearly: repeatsYearly, setAside: setAside)
    }
}

/// What a category's target asks for in one month.
public struct BudgetTargetFigures: Hashable, Sendable {
    public let target: Target
    public let needed: Decimal
    /// What of `needed` is not assigned yet; a snoozed month still says it.
    public let underfunded: Decimal
    /// From 0 to 1.
    public let progress: Double
    /// What counts toward a target by a date's amount; nil for a monthly target.
    public let saved: Decimal?
    public let isSnoozed: Bool

    /// What the target still asks this month; nothing while it is snoozed.
    public var openNeed: Decimal { isSnoozed ? 0 : underfunded }
}

/// Abakus's `Budget.Target`: months are month indexes, amounts are rounded up to the cent where they are spread.
enum TargetCalculation {
    struct Version {
        let month: Int
        let target: Target
    }

    struct Row {
        let month: Int
        let carried: Decimal
        let assigned: Decimal
        let isSnoozed: Bool
    }

    /// The version in effect in `month` with the month its current cycle began.
    static func inEffect(_ versions: [Version], at month: Int) -> (version: Target, cycleStart: Int)? {
        let upToMonth = versions.filter { $0.month <= month }.sorted { $0.month > $1.month }
        guard let latest = upToMonth.first, !latest.target.isEnded else { return nil }
        return (latest.target, cycleStart(of: latest, earlier: Array(upToMonth.dropFirst()), at: month))
    }

    /// A cycle begins the month after the last due month a version reached, else with the first version of the run.
    private static func cycleStart(of version: Version, earlier: [Version], at month: Int) -> Int {
        guard version.target.cadence == .byDate else { return version.month }
        let run = Array(([version] + earlier.prefix { $0.target.cadence == .byDate }).reversed())
        let due = dueMonth(version.target, at: month)
        let ends = run.dropFirst().map(\.month) + [due]
        let lastDue = zip(run, ends).flatMap { reached($0.0, before: $0.1) }.filter { $0 < due }.max()
        return lastDue.map { $0 + 1 } ?? run[0].month
    }

    private static func reached(_ version: Version, before until: Int) -> [Int] {
        let first = dueMonth(version.target, at: version.month)
        guard version.target.repeatsYearly else { return first < until ? [first] : [] }
        return Array(stride(from: first, to: until, by: 12))
    }

    static func dueMonth(_ target: Target, at month: Int) -> Int {
        let due = target.dueOn?.monthIndex ?? month
        guard target.repeatsYearly, due < month else { return due }
        return due + (month - due + 11) / 12 * 12
    }

    static func figures(
        _ target: Target, cycleStart: Int, row: Row, assignedIn: (Int) -> Decimal
    ) -> BudgetTargetFigures {
        let (asks, savedBefore) = asks(target, cycleStart: cycleStart, row: row, assignedIn: assignedIn)
        let needed = asks.map { max($0, 0) } ?? 0
        let underfunded = asks.map { max(Amount.round($0 - row.assigned), 0) } ?? 0
        let saved = Amount.round(savedBefore + row.assigned)
        return BudgetTargetFigures(
            target: target, needed: needed, underfunded: underfunded,
            progress: progress(target, needed: needed, underfunded: underfunded, saved: saved),
            saved: target.cadence == .byDate ? saved : nil, isSnoozed: row.isSnoozed)
    }

    /// What the month asks (negative for a surplus, nil once a dated target is over) and what was saved before.
    private static func asks(
        _ target: Target, cycleStart: Int, row: Row, assignedIn: (Int) -> Decimal
    ) -> (Decimal?, Decimal) {
        switch (target.cadence, target.setAside) {
        case (.monthly, true): return (target.amount, 0)
        case (.monthly, false): return (Amount.round(target.amount - row.carried), 0)
        default:
            let saved =
                target.setAside ? Amount.sum((cycleStart..<max(cycleStart, row.month)).map(assignedIn)) : row.carried
            let months = dueMonth(target, at: row.month) - row.month + 1
            return (spread(Amount.round(target.amount - saved), over: months), saved)
        }
    }

    private static func spread(_ missing: Decimal, over months: Int) -> Decimal? {
        guard months >= 1 else { return nil }
        guard missing > 0 else { return missing }
        var share = missing / Decimal(months)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &share, 2, .up)
        return rounded
    }

    private static func progress(_ target: Target, needed: Decimal, underfunded: Decimal, saved: Decimal)
        -> Double
    {
        if target.cadence == .byDate {
            guard target.amount > 0 else { return 1 }
            return min(max(double(saved) / double(target.amount), 0), 1)
        }
        guard underfunded > 0 else { return 1 }
        return double(max(needed - underfunded, 0)) / double(max(needed, underfunded))
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

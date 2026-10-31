import Foundation

public enum QuickBudgetFill: String, CaseIterable, Sendable {
    case assignedLastMonth
    case outflowsLastMonth
    case averageOutflows
    case averageOutflowsLastYear
    case scheduledOutflows
    case balanceToZero
    case zero
}

public struct QuickBudgetOption: Hashable, Sendable {
    public let fill: QuickBudgetFill
    public let label: String
    public let amount: Decimal
}

public struct QuickBudgetConfirmation: Hashable, Sendable {
    public let instruction: String
    public let content: String
    public let button: String
}

public struct QuickBudgetMenuItem: Hashable, Sendable {
    public let label: String
    /// Nil for the two disabled headings.
    public let fill: QuickBudgetFill?
    public let confirmation: QuickBudgetConfirmation?
}

public struct QuickBudgetHistory: Hashable, Sendable {
    let threeMonths: Int
    let year: Int

    /// Between 4 and 11 months of last year have data: the year average names its month count.
    public var isPartialYear: Bool { year > 3 && year < 12 }

    var fills: [QuickBudgetFill] {
        var fills: [QuickBudgetFill] = [.assignedLastMonth, .outflowsLastMonth]
        if threeMonths > 1 { fills.append(.averageOutflows) }
        if year > 3 { fills.append(.averageOutflowsLastYear) }
        return fills + [.scheduledOutflows, .balanceToZero]
    }

    func cellLabel(_ fill: QuickBudgetFill) -> String {
        fill == .zero ? "" : menuLabel(fill, zero: "") + ":"
    }

    func menuLabel(_ fill: QuickBudgetFill, zero: String) -> String {
        switch fill {
        case .assignedLastMonth: "Zugewiesen im Vormonat"
        case .outflowsLastMonth: "Ausgegeben im Vormonat"
        case .averageOutflows: "Im Schnitt ausgegeben, letzte \(threeMonths) Monate"
        case .averageOutflowsLastYear:
            "Im Schnitt ausgegeben, letztes Jahr" + (isPartialYear ? " (nur \(year) Monate)" : "")
        case .scheduledOutflows: "Geplante Ausgaben diesen Monat"
        case .balanceToZero: "Verfügbar auf null bringen"
        case .zero: "\(zero) (alle Zuweisungen zurücksetzen)"
        }
    }
}

extension BudgetSheet {
    public func quickBudgetHistory(month: DateWithoutTime) -> QuickBudgetHistory {
        QuickBudgetHistory(threeMonths: historyMonths(3, before: month), year: historyMonths(12, before: month))
    }

    /// The Zugewiesen cell's drop-down without its calculator row.
    public func quickBudgetOptions(categoryId: String, month: DateWithoutTime) -> [QuickBudgetOption] {
        let history = quickBudgetHistory(month: month)
        return history.fills.map { fill in
            QuickBudgetOption(
                fill: fill, label: history.cellLabel(fill),
                amount: quickBudgetAmount(fill, categoryId: categoryId, month: month))
        }
    }

    public func quickBudgetMenu(month: DateWithoutTime, formatter: BudgetFormatter) -> [QuickBudgetMenuItem] {
        let history = quickBudgetHistory(month: month)
        let zero = formatter.currencySimple(0)
        func item(_ fill: QuickBudgetFill) -> QuickBudgetMenuItem {
            QuickBudgetMenuItem(
                label: "   " + history.menuLabel(fill, zero: zero), fill: fill,
                confirmation: quickBudgetConfirmation(fill, month: month, history: history, formatter: formatter))
        }
        return [QuickBudgetMenuItem(label: "Leere Zuweisungen füllen mit:", fill: nil, confirmation: nil)]
            + history.fills.map(item)
            + [QuickBudgetMenuItem(label: "Alle Zuweisungen setzen auf:", fill: nil, confirmation: nil), item(.zero)]
    }

    /// Nil for a fill the month menu does not offer.
    public func quickBudgetConfirmation(_ fill: QuickBudgetFill, month: DateWithoutTime, formatter: BudgetFormatter)
        -> QuickBudgetConfirmation?
    {
        let history = quickBudgetHistory(month: month)
        guard fill == .zero || history.fills.contains(fill) else { return nil }
        return quickBudgetConfirmation(fill, month: month, history: history, formatter: formatter)
    }

    private func quickBudgetConfirmation(
        _ fill: QuickBudgetFill, month: DateWithoutTime, history: QuickBudgetHistory, formatter: BudgetFormatter
    ) -> QuickBudgetConfirmation {
        let previous = formatter.monthAndShortYear(month.addingMonths(-1))
        let question: String
        switch fill {
        case .assignedLastMonth: question = "Leere Zuweisungen mit den Zuweisungen aus \(previous) füllen?"
        case .outflowsLastMonth: question = "Leere Zuweisungen mit den Ausgaben aus \(previous) füllen?"
        case .averageOutflows:
            question =
                "Leere Zuweisungen mit den durchschnittlichen Ausgaben der letzten \(history.threeMonths) Monate füllen?"
        case .averageOutflowsLastYear:
            question = "Leere Zuweisungen mit den durchschnittlichen Ausgaben des letzten Jahres füllen?"
        case .scheduledOutflows:
            question =
                "Leere Zuweisungen mit den geplanten Ausgaben für \(formatter.monthAndShortYear(month)) füllen?"
        case .balanceToZero: question = "Leere Zuweisungen so füllen, dass Verfügbar auf null kommt?"
        case .zero:
            return QuickBudgetConfirmation(
                instruction: "Alle Zuweisungen im \(formatter.monthName(month.month)) zurücksetzen?",
                content: "<i>Jede</i> Kategorie bekommt \(formatter.currencySimple(0)) zugewiesen. "
                    + Self.cannotBeUndone,
                button: "Zurücksetzen")
        }
        return QuickBudgetConfirmation(
            instruction: question, content: Self.cannotBeUndone, button: "Leere Zuweisungen füllen")
    }

    static let cannotBeUndone = "Das lässt sich nicht rückgängig machen."

    public func quickBudgetAmount(_ fill: QuickBudgetFill, categoryId: String, month: DateWithoutTime) -> Decimal {
        let lastMonth = self.month(month.addingMonths(-1))?.category(categoryId)
        switch fill {
        case .assignedLastMonth: return lastMonth?.assigned ?? 0
        case .outflowsLastMonth: return lastMonth?.spent ?? 0
        case .averageOutflows:
            return averageOutflows(over: historyMonths(3, before: month), categoryId: categoryId, month: month)
        case .averageOutflowsLastYear:
            return averageOutflows(over: historyMonths(12, before: month), categoryId: categoryId, month: month)
        case .scheduledOutflows: return scheduledOutflows(categoryId: categoryId, month: month)
        case .balanceToZero:
            guard let figures = self.month(month)?.category(categoryId) else { return 0 }
            return Amount.round(figures.assigned - figures.balance)
        case .zero: return 0
        }
    }

    public func scheduledOutflows(categoryId: String, month: DateWithoutTime) -> Decimal {
        let first = month.firstOfMonth
        let last = month.lastOfMonth
        let onBudget = Set(budget.accounts.filter(\.onBudget).map(\.id))
        var total: Decimal = 0
        for scheduled in budget.scheduledTransactions where onBudget.contains(scheduled.accountId) {
            let outflow: Decimal
            if scheduled.isSplit {
                outflow = Amount.sum(
                    scheduled.subtransactions.filter { $0.categoryId == categoryId }.map { Amount.round($0.outflow) })
            } else {
                outflow = scheduled.categoryId == categoryId ? scheduled.outflow : 0
            }
            guard outflow != 0 else { continue }
            let occurrences = scheduled.occurrences(from: first, through: last)
            total = Amount.round(total + Amount.round(outflow * Decimal(occurrences)))
        }
        return total
    }

    /// The averages are anchored on today's month, not on the month asked about.
    private func historyStart(for month: DateWithoutTime) -> Int {
        let current = today.monthIndex
        return month.monthIndex > current ? current + 1 : current
    }

    /// The furthest of the last `count` months with real data, not the number of such months.
    public func historyMonths(_ count: Int, before month: DateWithoutTime) -> Int {
        let start = historyStart(for: month)
        var valid = 0
        for back in stride(from: 1, through: count, by: 1) {
            guard let earlier = self.month(DateWithoutTime(monthIndex: start - back)) else { break }
            if earlier.hasRealData { valid = back }
        }
        return valid
    }

    private func averageOutflows(over count: Int, categoryId: String, month: DateWithoutTime) -> Decimal {
        let start = historyStart(for: month)
        var total: Decimal = 0
        var months = 0
        for back in stride(from: 1, through: count, by: 1) {
            guard let earlier = self.month(DateWithoutTime(monthIndex: start - back)) else { break }
            total += earlier.category(categoryId)?.spent ?? 0
            months += 1
        }
        return Amount.round(total / Decimal(max(months, 1)))
    }
}

extension Budget {
    mutating func quickBudget(month: DateWithoutTime, fill: QuickBudgetFill, today: DateWithoutTime) {
        let sheet = budgetSheet(today: today, including: [month])
        guard let figures = sheet.month(month) else { return }
        for master in sheet.categoryGroups {
            for sub in master.categories {
                if fill == .zero {
                    setAssignment(0, month: month, categoryId: sub.id)
                    continue
                }
                guard figures.category(sub.id)?.assigned == 0 else { continue }
                let amount = sheet.quickBudgetAmount(fill, categoryId: sub.id, month: month)
                guard amount.isFinite else { continue }
                setAssignment(amount, month: month, categoryId: sub.id)
            }
        }
    }
}

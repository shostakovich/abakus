import AbakusCore
import Foundation

extension TransactionEditor {
    public func repeatChosen(_ choice: Repeat.Choice) {
        repeatChoice = choice
        repeats = (repeats ?? .monthly).choosing(choice)
    }

    public func repeatCountChosen(_ count: Int) {
        guard Repeat.counts.contains(count) else { return }
        repeatChoice = .custom
        repeats = .every(count, repeats?.unit ?? .week)
    }

    public func repeatUnitChosen(_ unit: Repeat.Unit) {
        repeatChoice = .custom
        repeats = .every(repeats?.count ?? 1, unit)
    }

    public var showsCustomRepeat: Bool { repeatChoice == .custom }

    public var customCount: Int { customRepeat.count ?? 1 }

    public var customUnit: Repeat.Unit { customRepeat.unit ?? .week }

    private var customRepeat: Repeat {
        guard let repeats, repeats.unit != nil else { return .customDefault }
        return repeats
    }

    public var customRepeatText: String {
        guard case .every(let count, let unit) = repeats else { return "" }
        return "\(count) \(Self.unitLabel(unit, count: count))"
    }

    public static func unitLabel(_ unit: Repeat.Unit, count: Int) -> String {
        switch unit {
        case .week: count == 1 ? "Woche" : "Wochen"
        case .month: count == 1 ? "Monat" : "Monate"
        }
    }

    public var followingDatesText: String? {
        guard let repeats else { return nil }
        let dates = repeats.dates(after: clone.date, count: 3)
        guard !dates.isEmpty else { return nil }
        return "Danach: " + dates.map(formatter.dateLong).joined(separator: " · ")
    }
}

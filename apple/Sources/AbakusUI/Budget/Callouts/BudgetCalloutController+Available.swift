import AbakusCore
import Foundation

public enum BudgetAvailableMode: Hashable, Sendable, CaseIterable {
    case cover, move

    public var title: String {
        switch self {
        case .cover: "Decken"
        case .move: "Verschieben"
        }
    }
}

public enum BudgetMoveDirection: Hashable, Sendable, CaseIterable {
    case give, take

    public var title: String {
        switch self {
        case .give: "Abgeben an"
        case .take: "Holen aus"
        }
    }
}

public struct BudgetCategoryChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public struct BudgetCategoryChoiceGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let categories: [BudgetCategoryChoice]
}

/// The Verfügbar popover of one category in one month.
public struct BudgetAvailableForm: Hashable, Sendable {
    public let month: DateWithoutTime
    public let categoryId: String
    public let categoryName: String
    public let monthTitle: String
    public let available: Decimal
    public let sources: [BudgetFundsSource]
    public let others: [BudgetCategoryChoiceGroup]
    public var mode: BudgetAvailableMode
    public var sourceId: String?
    public var amount: String
    public var direction: BudgetMoveDirection
    public var otherId: String
    public internal(set) var error: String?

    public var isOverspent: Bool { available < 0 }

    public var source: BudgetFundsSource? {
        sources.first { $0.categoryId == sourceId } ?? sources.first
    }
}

extension BudgetCalloutController {
    static let nothingToCover = "Daraus lässt sich nichts decken."
    static let noSources = "Kein Geld in „Zu verteilen“ oder anderen Kategorien."
    static let missingAmount = "Bitte einen Betrag angeben."
    static let amountNotPositive = "Bitte einen Betrag über null angeben, etwa 12,50."

    func availableForm(month date: DateWithoutTime, categoryId: String) -> BudgetAvailableForm? {
        let sheet = budget.sheet
        guard let month = sheet.month(date),
            let category = sheet.categoryGroups.flatMap(\.categories).first(where: { $0.id == categoryId })
        else { return nil }
        let available = month.category(categoryId)?.balance ?? 0
        let underfunded = month.category(categoryId)?.target?.underfunded ?? 0
        let amount = available > 0 ? available : underfunded > 0 ? underfunded : max(-available, 0)
        return BudgetAvailableForm(
            month: date, categoryId: categoryId, categoryName: category.name,
            monthTitle: formatter.monthHeader(date), available: available,
            sources: sheet.coverSources(for: categoryId, in: date), others: categoryChoices(excluding: categoryId),
            mode: available < 0 ? .cover : .move,
            amount: formatter.currencyNoSymbol(amount),
            direction: available > 0 ? .give : .take, otherId: sheet.readyToAssignCategoryId)
    }

    public var readyToAssignCategoryId: String { budget.sheet.readyToAssignCategoryId }

    func categoryChoices(excluding excluded: String? = nil) -> [BudgetCategoryChoiceGroup] {
        budget.sheet.categoryGroups.compactMap { master in
            let categories = master.categories.filter { $0.id != excluded }
                .map { BudgetCategoryChoice(id: $0.id, name: $0.name) }
            guard !categories.isEmpty else { return nil }
            return BudgetCategoryChoiceGroup(id: master.id, name: master.name, categories: categories)
        }
    }

    /// Popover amounts read like the budget's assignment cells, where "12.5" is 125.
    func typedAmount(_ text: String) -> Decimal? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : formatter.parseBudgetAmount(text)
    }

    func amountError(_ text: String) -> String {
        typedAmount(text) == nil ? Self.missingAmount : Self.amountNotPositive
    }

    public var availableMode: BudgetAvailableMode {
        get { availableForm?.mode ?? .move }
        set { changeAvailableForm { $0.mode = newValue } }
    }

    public var coverSourceId: String {
        get { availableForm?.source?.categoryId ?? "" }
        set { changeAvailableForm { $0.sourceId = newValue } }
    }

    public var moveAmount: String {
        get { availableForm?.amount ?? "" }
        set { changeAvailableForm { $0.amount = newValue } }
    }

    public var moveDirection: BudgetMoveDirection {
        get { availableForm?.direction ?? .give }
        set { changeAvailableForm { $0.direction = newValue } }
    }

    public var moveOtherId: String {
        get { availableForm?.otherId ?? readyToAssignCategoryId }
        set { changeAvailableForm { $0.otherId = newValue } }
    }

    private func changeAvailableForm(_ change: (inout BudgetAvailableForm) -> Void) {
        guard var form = availableForm else { return }
        change(&form)
        form.error = nil
        availableForm = form
    }

    public var coverLabel: String {
        "Decke \(formatter.currency(-min(availableForm?.available ?? 0, 0))) aus"
    }

    public func coverSourceLabel(_ source: BudgetFundsSource) -> String {
        "\(source.name) · \(formatter.currency(source.available))"
    }

    public var remainingLabel: String {
        guard let source = availableForm?.source else { return "" }
        return source.isReadyToAssign ? "Zu verteilen danach" : "\(source.name) danach"
    }

    public var remainingText: String {
        guard let form = availableForm, let source = form.source else { return "" }
        return formatter.currency(source.remaining(afterCovering: form.available))
    }

    public func coverClicked() {
        guard let form = availableForm, let source = form.source,
            case let amount = source.coverAmount(overspent: form.available), amount > 0
        else {
            availableForm?.error = Self.nothingToCover
            return
        }
        move(amount, in: form.month, from: source.categoryId, to: form.categoryId)
    }

    public func moveClicked() {
        guard let form = availableForm else { return }
        guard let amount = typedAmount(form.amount), amount > 0 else {
            availableForm?.error = amountError(form.amount)
            return
        }
        let (from, to) =
            form.direction == .give ? (form.categoryId, form.otherId) : (form.otherId, form.categoryId)
        move(amount, in: form.month, from: from, to: to)
    }

    func move(_ amount: Decimal, in month: DateWithoutTime, from: String, to: String) {
        close()
        budget.perform(.moveAssigned(month: month, from: from, to: to, amount: amount))
    }

    public func availableCancelled() {
        close()
    }

    public func editCategoryClicked() {
        guard let form = availableForm else { return }
        budget.present(.editCategory(categoryId: form.categoryId, month: form.month))
    }
}

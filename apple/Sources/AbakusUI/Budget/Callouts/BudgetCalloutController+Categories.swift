import AbakusCore
import Foundation

public struct BudgetCategoryChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public struct BudgetCategoryChoiceGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let categories: [BudgetCategoryChoice]
}

public struct BudgetCategoryForm: Hashable, Sendable {
    public let categoryId: String
    public let isMaster: Bool
    public let isNew: Bool
    public let month: DateWithoutTime
    var originalName: String
    public var name: String
    public internal(set) var closesOnClickOutside = true
    public internal(set) var focusRequest = 0
    public internal(set) var target: BudgetTargetForm?
    public let canDelete: Bool
    public internal(set) var deletion: BudgetCategoryDeletion?

    public var hasTarget: Bool { !isMaster && !isNew }

    public var title: String {
        switch (isMaster, isNew) {
        case (true, true): "Neue Kategoriegruppe"
        case (true, false): "Kategoriegruppe bearbeiten"
        case (false, true): "Neue Kategorie"
        case (false, false): "Kategorie bearbeiten"
        }
    }

    public var deleteTitle: String {
        isMaster ? "Gruppe löschen" : "Kategorie löschen"
    }

    public var deletionTitle: String { "Kategorie „\(originalName)“ löschen" }
}

public struct BudgetCategoryDeletion: Hashable, Sendable {
    public static let noSuccessor = "Es gibt keine andere Kategorie, die alles übernehmen kann."
    public static let successorLabel = "Buchungen, Zuweisungen und Geld gehen in"
    public static let reconciledWarning = "Auch abgeglichene Buchungen bekommen die neue Kategorie."

    public let successors: [BudgetCategoryChoiceGroup]
    public let changesReconciledTransactions: Bool
    public var successorId: String?
}

extension BudgetCalloutController {
    static let renameRefusal = "Bitte einen anderen Namen wählen"

    public var categoryName: String {
        get { category?.name ?? "" }
        set { category?.name = newValue }
    }

    func categoryForm(_ id: String, isNew: Bool, month: DateWithoutTime? = nil) -> BudgetCategoryForm? {
        let budget = store.budget
        let month = month?.firstOfMonth ?? self.budget.focusMonth
        if let master = budget.budgetCategoryGroups.first(where: { $0.id == id }) {
            return BudgetCategoryForm(
                categoryId: id, isMaster: true, isNew: isNew, month: month, originalName: master.name,
                name: master.name, canDelete: master.categories.isEmpty)
        }
        guard let sub = budget.category(withId: id) else { return nil }
        return BudgetCategoryForm(
            categoryId: id, isMaster: false, isNew: isNew, month: month, originalName: sub.name, name: sub.name,
            canDelete: true)
    }

    func addCategoryGroup() -> BudgetPopup? {
        reset()
        let id = EntityID.createUID()
        budget.perform(.addCategoryGroup(groupId: id))
        guard let form = categoryForm(id, isNew: true) else { return nil }
        budget.scroll(to: 0)
        category = form
        return .editCategory(categoryId: id)
    }

    func addCategory(groupId: String) -> BudgetPopup? {
        reset()
        let id = EntityID.createUID()
        budget.perform(.addCategory(groupId: groupId, categoryId: id))
        guard let form = categoryForm(id, isNew: true) else { return nil }
        revealGroup(groupId)
        category = form
        return .editCategory(categoryId: id)
    }

    func revealGroup(_ masterId: String) {
        guard let group = budget.groups.first(where: { $0.id == masterId }),
            let top = budget.groups.top(of: masterId)
        else { return }
        let viewport = budget.layout.viewportHeight
        if top - budget.scrollOffset + group.height > viewport {
            budget.scroll(to: top + group.height - viewport)
        } else if top < budget.scrollOffset {
            budget.scroll(to: top)
        }
    }

    public func categoryDone() {
        guard saveOpenTarget(), var form = category else { return }
        form.closesOnClickOutside = false
        category = form
        guard rename(form) != nil else { return }
        close()
    }

    /// The title renames in place; a refused name stays to be changed.
    public func categoryNameSubmitted() {
        guard let form = category, !form.isNew, let name = rename(form) else { return }
        category?.originalName = name
        category?.name = name
    }

    /// The trimmed name once saved, nil when it is refused.
    private func rename(_ form: BudgetCategoryForm) -> String? {
        let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != form.originalName else { return name }
        let command: BudgetCommand =
            form.isMaster
            ? .renameCategoryGroup(groupId: form.categoryId, name: name)
            : .renameCategory(categoryId: form.categoryId, name: name)
        do {
            try store.perform(command)
            return name
        } catch {
            guard !dialogs.isPresenting(ownedBy: self) else { return nil }
            dialogs.show(.message(Self.renameRefusal, error.localizedDescription), owner: self) { [weak self] in
                self?.category?.focusRequest += 1
            }
            return nil
        }
    }

    public func categoryCancelled() {
        guard let form = category else { return }
        close()
        guard form.isNew else { return }
        budget.perform(
            form.isMaster
                ? .deleteCategoryGroup(groupId: form.categoryId) : .discardCategory(categoryId: form.categoryId))
    }

    public func deleteCategoryClicked() {
        guard let form = category, form.canDelete else { return }
        if form.isMaster {
            close()
            budget.perform(.deleteCategoryGroup(groupId: form.categoryId))
            return
        }
        category?.target = nil
        category?.deletion = BudgetCategoryDeletion(
            successors: categoryChoices(excluding: form.categoryId),
            changesReconciledTransactions: store.budget.hasReconciledTransactions(inCategory: form.categoryId))
    }

    public var deletionSuccessorId: String? {
        get { category?.deletion?.successorId }
        set { category?.deletion?.successorId = newValue }
    }

    public func deletionCancelled() {
        category?.deletion = nil
        category?.focusRequest += 1
    }

    func deletionEscaped() -> Bool {
        guard category?.deletion != nil else { return false }
        deletionCancelled()
        return true
    }

    public func confirmDeletionClicked() {
        guard let form = category, let successor = form.deletion?.successorId else { return }
        close()
        budget.perform(.deleteCategory(categoryId: form.categoryId, into: successor))
    }
}

extension BudgetCalloutController {
    func categoryChoices(excluding excluded: String) -> [BudgetCategoryChoiceGroup] {
        budget.sheet.categoryGroups.compactMap { master in
            let categories = master.categories.filter { $0.id != excluded }
                .map { BudgetCategoryChoice(id: $0.id, name: $0.name) }
            guard !categories.isEmpty else { return nil }
            return BudgetCategoryChoiceGroup(id: master.id, name: master.name, categories: categories)
        }
    }
}

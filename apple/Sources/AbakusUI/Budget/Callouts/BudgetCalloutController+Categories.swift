import AbakusCore
import Foundation

public struct BudgetCategoryForm: Hashable, Sendable {
    public let categoryId: String
    public let isMaster: Bool
    public let isNew: Bool
    public let month: DateWithoutTime
    let originalName: String
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
        let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != form.originalName else {
            close()
            return
        }
        let command: BudgetCommand =
            form.isMaster
            ? .renameCategoryGroup(groupId: form.categoryId, name: name)
            : .renameCategory(categoryId: form.categoryId, name: name)
        do {
            try store.perform(command)
        } catch {
            guard !dialogs.isPresenting(ownedBy: self) else { return }
            dialogs.show(.message(Self.renameRefusal, error.localizedDescription), owner: self) { [weak self] in
                self?.category?.focusRequest += 1
            }
            return
        }
        close()
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

import AbakusCore
import Foundation

struct FocusMove: Hashable {
    var after: EditorFieldID
    var backward: Bool
}

extension TransactionEditor {
    static let invalidDateTitle = "Ungültiges Datum"

    @discardableResult
    func commit(_ field: EditorFieldID, reason: CommitReason) -> FocusMove? {
        if let subId = field.subId { return commitSub(subId, column: field.column, reason: reason) }
        switch field.column {
        case .account: return commitAccount(reason: reason)
        case .date: commitDate()
        case .payee: return commitPayee(reason: reason)
        case .category: return commitCategory(reason: reason)
        case .memo:
            clone.memo = text(field).isEmpty ? nil : text(field)
        case .outflow, .inflow: commitAmount(field)
        case .frequency: break
        }
        return nil
    }

    func apply(_ move: FocusMove) {
        let target = tabOrder.contains(.field(move.after)) ? move.after : EditorFieldID.main(.payee)
        moveFocus(after: target, backward: move.backward)
    }

    private func moveAfter(_ field: EditorFieldID, _ reason: CommitReason) -> FocusMove? {
        guard case .clickedItem(let backward) = reason else { return nil }
        return FocusMove(after: field, backward: backward)
    }

    /// An unreadable or far-off date reverts and blocks the next save.
    private func commitDate() {
        let field = EditorFieldID.main(.date)
        let typed = text(field).trimmingCharacters(in: .whitespaces)
        let formatter = formatter
        guard !typed.isEmpty else {
            setText(field, formatter.dateShort(clone.date))
            return
        }
        if let date = formatter.parseDate(typed, today: today) {
            if let refusal = dateRefusal(date, shownAs: typed) {
                rejectDate(refusal)
                return
            }
            clone.date = date
            setText(field, formatter.dateShort(date))
            return
        }
        rejectDate(
            "Nicht verstanden: „<b>\(String(typed.prefix(12)))</b>“<br/>Datum im Format "
                + "<b>\(formatter.shortDatePattern)</b> eingeben.")
    }

    func dateRefusal(_ date: DateWithoutTime, shownAs text: String) -> String? {
        if isScheduled && date < today {
            return "Datum außerhalb des Bereichs: „<b>\(text)</b>“<br/>Geplante Buchungen beginnen frühestens heute."
        }
        guard abs(today.days(until: date)) > 10 * 365 else { return nil }
        return "Datum außerhalb des Bereichs: „<b>\(text)</b>“<br/>Das Datum muss innerhalb von 10 Jahren um heute "
            + "liegen."
    }

    func rejectDate(_ message: String) {
        setText(.main(.date), formatter.dateShort(clone.date))
        dateCallout = EditorDateCallout(title: Self.invalidDateTitle, message: message)
        blockNextSave = true
        refocusRequest = .main(.date)
    }

    private func commitAccount(reason: CommitReason) -> FocusMove? {
        let field = EditorFieldID.main(.account)
        let typed = text(field).trimmingCharacters(in: .whitespaces).lowercased()
        let candidates = catalog.accountItems(for: clone).compactMap { item -> Account? in
            guard case .account(let id) = item.kind else { return nil }
            return budget.account(withId: id)
        }
        if let chosen = candidates.first(where: { $0.name.lowercased() == typed }) {
            clone.accountId = chosen.id
        }
        setText(field, budget.account(withId: clone.accountId)?.name ?? "")
        return moveAfter(field, reason)
    }

    private func commitPayee(reason: CommitReason) -> FocusMove? {
        let field = EditorFieldID.main(.payee)
        let typed = text(field).trimmingCharacters(in: .whitespaces)
        var skipCategory = false
        var prompt = Self.categoryPrompt
        let lockedToSplit = mode == .existing && budget.isTransferFromSplit(original)
        if Payee.isTransferPayeeName(typed) {
            let name = Payee.transferTargetAccountName(typed) ?? ""
            if isSplitMode { return refusePayee(.splitCannotBeTransfer) }
            if lockedToSplit && !Payee.sameName(typed, originalPayeeName) {
                return refusePayee(.transferFromSplitPayeeLocked)
            }
            guard let target = budget.account(named: name) else {
                return refusePayee(.invalidTransferPayee(name))
            }
            if target.id == clone.accountId { return refusePayee(.transferToSameAccount) }
            if target.onBudget && isOnBudget {
                prompt = Self.categoryNotNeeded
                if clone.categoryId == nil { skipCategory = true }
            }
            clone.transfer(to: target.id)
        } else {
            if lockedToSplit && !Payee.sameName(typed, originalPayeeName) {
                return refusePayee(.transferFromSplitPayeeLocked)
            }
            if budget.isTransfer(clone) { clone.payeeId = nil }
        }
        payeeName = budget.properPayeeName(typed)
        setText(field, payeeName)
        autoFillFields()
        guard reason != .lostFocus else { return nil }
        categoryPrompts[nil] = prompt
        let backward = if case .clickedItem(let backward) = reason { backward } else { false }
        let after = skipCategory && tabOrder.contains(.field(.main(.category))) ? EditorFieldID.main(.category) : field
        return FocusMove(after: after, backward: backward)
    }

    private func refusePayee(_ error: BudgetError) -> FocusMove? {
        setText(.main(.payee), payeeName)
        showRefusal(error, refocus: nil)
        return nil
    }

    func showRefusal(_ error: BudgetError, refocus: EditorFieldID?) {
        showMessage(.message(error.dialogInstruction, error.dialogContent ?? ""), refocus: refocus)
    }

    /// The payee's memorized values go into the empty fields of an unsplit clone.
    private func autoFillFields() {
        guard !isSplitMode, clone.subtransactions.isEmpty,
            let fill = budget.autoFill(payeeName: payeeName, accountId: clone.accountId, settings: autoFillSettings)
        else { return }
        if clone.categoryId == nil, let categoryId = fill.categoryId {
            clone.categoryId = categoryId
            setText(.main(.category), categoryText(categoryId))
        }
        if (clone.memo ?? "").isEmpty, let memo = fill.memo {
            clone.memo = memo
            setText(.main(.memo), memo)
        }
        if clone.amount == 0, let amount = fill.amount {
            clone.amount = amount
            refreshAmountTexts(subId: nil)
        }
    }

    private func commitCategory(reason: CommitReason) -> FocusMove? {
        let field = EditorFieldID.main(.category)
        let typed = text(field).trimmingCharacters(in: .whitespaces)
        if typed.isEmpty {
            clone.categoryId = nil
            return nil
        }
        if typed.lowercased() == DefaultCategories.splitCategoryName.lowercased() {
            if let leader {
                setText(field, categoryText(clone.categoryId))
                showRefusal(.ledTransaction(leader), refocus: field)
                return nil
            }
            if clone.categoryId != EntityID.splitCategory && budget.isTransfer(clone) {
                setText(field, categoryText(clone.categoryId))
                showMessage(
                    .message(
                        "Diese Buchung lässt sich nicht aufteilen.",
                        "Diese Buchung ist eine Umbuchung und lässt sich darum nicht aufteilen. Um eine Umbuchung "
                            + "aufzuteilen, mache die Buchung selbst nicht zur Umbuchung, sondern teile sie auf und "
                            + "mache die Teile zu Umbuchungen."), refocus: field)
                return nil
            }
            clone.categoryId = EntityID.splitCategory
            setText(field, DefaultCategories.splitCategoryName)
            setSplitMode(true)
            return moveAfter(field, reason)
        }
        guard let categoryId = lookUpCategory(typed, fullNameOnly: false) else {
            askForNewCategory(typed, field: field)
            return nil
        }
        clone.categoryId = categoryId
        setText(field, categoryText(categoryId))
        if isSplitMode { setSplitMode(false) }
        return moveAfter(field, reason)
    }

    func lookUpCategory(_ typed: String, fullNameOnly: Bool) -> String? {
        if let income = budget.incomeCategory(label: typed) { return income }
        if typed.contains(":") { return budget.category(fullName: typed)?.id }
        return fullNameOnly ? nil : budget.category(named: typed)?.id
    }

    func askForNewCategory(_ typed: String, field: EditorFieldID) {
        var (master, name) = CategoryNames.components(typed)
        if typed.trimmingCharacters(in: .whitespaces).lowercased() == CategoryNames.addNewCategory.lowercased() {
            (master, name) = ("", "")
        } else if CategoryNames.isIncomeGroupName(master) {
            showMessage(
                .message(Self.otherCategoryName, BudgetError.categoryCantBeIncome.errorDescription ?? ""),
                refocus: field)
            return
        } else if CategoryNames.isReservedGroupName(master) {
            master = ""
        }
        pendingCategoryField = field
        addCategoryForm = AddCategoryForm(masterName: master, name: name)
    }

    static let otherCategoryName = "Bitte einen anderen Kategorienamen wählen."

    public func addCategoryConfirmed(masterName: String, name: String) {
        guard var form = addCategoryForm else { return }
        do {
            try store.perform(.addNamedCategory(groupName: masterName, name: name))
        } catch {
            form.masterName = masterName
            form.name = name
            addCategoryForm = form
            let message = TaskDialog<MessageChoice>.message(
                Self.otherCategoryName, error.localizedDescription)
            dialogs.show(message, owner: self) { [weak self] in self?.addCategoryForm?.refocusRequest += 1 }
            return
        }
        addCategoryForm = nil
        let field = pendingCategoryField ?? .main(.category)
        pendingCategoryField = nil
        guard
            let added = budget.category(
                fullName: "\(masterName.trimmingCharacters(in: .whitespaces)): "
                    + name.trimmingCharacters(in: .whitespaces))?.id
        else { return }
        setCategory(added, on: field)
        if isSplitMode && !field.isSub { setSplitMode(false) }
        if focus != .field(field) { setFocus(.field(field), commitCurrent: false) }
        moveFocus(after: field, backward: false)
    }

    public func addCategoryCancelled() {
        guard addCategoryForm != nil else { return }
        addCategoryForm = nil
        let field = pendingCategoryField ?? .main(.category)
        pendingCategoryField = nil
        let categoryId =
            field.subId.map { id in clone.subtransactions.first { $0.id == id }?.categoryId } ?? clone.categoryId
        setText(field, categoryText(categoryId))
        if focus != .field(field) { setFocus(.field(field), commitCurrent: false) } else { selectAll(field) }
    }

    private func setCategory(_ categoryId: String, on field: EditorFieldID) {
        if let subId = field.subId, let index = clone.subtransactions.firstIndex(where: { $0.id == subId }) {
            clone.subtransactions[index].categoryId = categoryId
        } else {
            clone.categoryId = categoryId
        }
        setText(field, categoryText(categoryId))
    }

    /// One signed amount; the setters are no-ops for an unchanged side.
    private func commitAmount(_ field: EditorFieldID) {
        let value = formatter.parseAmount(text(field))
        var amount = clone.amount
        if field.column == .inflow {
            if value != clone.inflow { amount = value }
        } else if value != clone.outflow {
            amount = -value
        }
        if amount != clone.amount && mode == .existing && budget.isTransferFromSplit(original) {
            refreshAmountTexts(subId: nil)
            showRefusal(.transferFromSplitAmountLocked, refocus: nil)
            return
        }
        clone.amount = amount
        refreshAmountTexts(subId: nil)
    }

    func refreshAmountTexts(subId: String?) {
        let amount =
            subId.map { id in clone.subtransactions.first { $0.id == id }?.amount ?? 0 } ?? clone.amount
        let formatter = formatter
        texts[EditorFieldID(subId: subId, column: .outflow)] = amount < 0 ? formatter.registerAmount(-amount) : ""
        texts[EditorFieldID(subId: subId, column: .inflow)] = amount >= 0 ? formatter.registerAmount(amount) : ""
    }

    func showMessage(_ message: TaskDialog<MessageChoice>, refocus: EditorFieldID?) {
        dropDown = nil
        dialogs.show(message, owner: self) { [weak self] in
            if let refocus { self?.setFocus(.field(refocus), commitCurrent: false) }
        }
    }
}

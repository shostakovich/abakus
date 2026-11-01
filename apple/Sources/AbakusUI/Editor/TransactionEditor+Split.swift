import AbakusCore
import Foundation

extension TransactionEditor {
    /// Leaving split mode keeps the lines aside like the clone keeps its sub-transactions.
    func setSplitMode(_ on: Bool) {
        guard on != isSplitMode else { return }
        if on {
            if clone.subtransactions.isEmpty {
                clone.subtransactions =
                    stashedSubtransactions.isEmpty
                    ? [newSubtransaction(), newSubtransaction()] : stashedSubtransactions
            }
            stashedSubtransactions = []
            subIds = clone.subtransactions.map(\.id)
            for id in subIds {
                resetSubTexts(id)
                categoryPrompts[id] = subCategoryPrompt(id)
            }
        } else {
            stashedSubtransactions = clone.subtransactions
            clone.subtransactions = []
            subIds = []
        }
        isSplitMode = on
    }

    func newSubtransaction() -> Subtransaction {
        Subtransaction(transactionId: clone.id, amount: 0)
    }

    public func addSubRow() {
        let id = appendSubRow()
        setFocus(.field(.sub(id, .payee)), commitCurrent: true)
    }

    @discardableResult
    func appendSubRow() -> String {
        let sub = newSubtransaction()
        clone.subtransactions.append(sub)
        subIds.append(sub.id)
        resetSubTexts(sub.id)
        categoryPrompts[sub.id] = Self.categoryPrompt
        return sub.id
    }

    public func deleteSubRow(_ id: String) {
        if focus?.field?.subId == id {
            closePopups()
            focus = nil
        }
        clone.subtransactions.removeAll { $0.id == id }
        subIds.removeAll { $0 == id }
        subPayeeNames[id] = nil
        for column in EditorColumn.allCases { texts[.sub(id, column)] = nil }
        categoryPrompts[id] = nil
    }

    public var remainingAmount: Decimal {
        SplitRules.unassigned(clone)
    }

    public var remainingText: String {
        let remaining = remainingAmount
        let text = formatter.currency(abs(remaining))
        return remaining < 0 ? "−" + text : remaining > 0 ? "+" + text : text
    }

    func commitSub(_ subId: String, column: EditorColumn, reason: CommitReason) -> FocusMove? {
        guard let index = clone.subtransactions.firstIndex(where: { $0.id == subId }) else { return nil }
        let field = EditorFieldID.sub(subId, column)
        let typed = text(field).trimmingCharacters(in: .whitespaces)
        switch column {
        case .payee: return commitSubPayee(index: index, field: field, typed: typed, reason: reason)
        case .category:
            if typed.isEmpty {
                clone.subtransactions[index].categoryId = nil
                return nil
            }
            guard let categoryId = lookUpCategory(typed, fullNameOnly: true) else {
                askForNewCategory(typed, field: field)
                return nil
            }
            clone.subtransactions[index].categoryId = categoryId
            setText(field, categoryText(categoryId))
            return reason == .lostFocus ? nil : FocusMove(after: field, backward: false)
        case .memo:
            clone.subtransactions[index].memo = typed.isEmpty ? nil : text(field)
        case .amount:
            commitSubAmount(index: index, field: field)
        default:
            break
        }
        return nil
    }

    private func commitSubPayee(index: Int, field: EditorFieldID, typed: String, reason: CommitReason) -> FocusMove? {
        guard Payee.isTransferPayeeName(typed) else {
            let name = typed.isEmpty ? "" : budget.properPayeeName(typed)
            clone.subtransactions[index].payeeId = name.isEmpty ? nil : budget.payee(named: name)?.id
            setSubPayee(name, index: index, field: field)
            categoryPrompts[field.subId] = Self.categoryPrompt
            return reason == .lostFocus ? nil : FocusMove(after: field, backward: false)
        }
        let restore = subPayeeText(clone.subtransactions[index])
        let name = Payee.transferTargetAccountName(typed) ?? ""
        guard let target = budget.account(named: name) else {
            setText(field, restore)
            showRefusal(.invalidTransferPayee(name), refocus: nil)
            return nil
        }
        guard target.id != clone.accountId else {
            setText(field, restore)
            showRefusal(.transferToSameAccount, refocus: nil)
            return nil
        }
        clone.subtransactions[index].transfer(to: target.id)
        setSubPayee(target.transferPayeeName, index: index, field: field)
        let notNeeded = target.onBudget && isOnBudget
        categoryPrompts[field.subId] = notNeeded ? Self.categoryNotNeeded : Self.categoryPrompt
        guard reason != .lostFocus else { return nil }
        let category = EditorFieldID(subId: field.subId, column: .category)
        let skip = notNeeded && clone.subtransactions[index].categoryId == nil && tabOrder.contains(.field(category))
        return FocusMove(after: skip ? category : field, backward: false)
    }

    private func setSubPayee(_ name: String, index: Int, field: EditorFieldID) {
        subPayeeNames[clone.subtransactions[index].id] = name
        setText(field, name)
        suggestSubCategory(index: index, payeeName: name)
    }

    private func suggestSubCategory(index: Int, payeeName: String) {
        guard clone.subtransactions[index].categoryId == nil,
            let categoryId = budget.autoFill(
                payeeName: payeeName, accountId: clone.accountId, settings: autoFillSettings)?.categoryId
        else { return }
        clone.subtransactions[index].categoryId = categoryId
        let field = EditorFieldID.sub(clone.subtransactions[index].id, .category)
        setText(field, categoryText(categoryId))
    }

    /// A last line that leaves money unassigned gets a successor.
    private func commitSubAmount(index: Int, field: EditorFieldID) {
        guard let subId = field.subId else { return }
        let old = clone.subtransactions[index].amount
        let amount = typedAmount(field)
        clone.subtransactions[index].amount = amount
        refreshAmountText(subId: subId)
        if amount != old && remainingAmount != 0 && subIds.last == subId && calculator == nil {
            let added = appendSubRow()
            refocusRequest = .sub(added, .payee)
        }
    }
}

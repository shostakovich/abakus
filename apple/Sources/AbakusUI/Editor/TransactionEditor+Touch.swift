import AbakusCore
import Foundation

/// The iPhone's and iPad's form sheet drives the Mac's edit row, so saving makes the same command.
extension TransactionEditor {
    /// The sheet's text fields follow the keyboard, never a commit's request to move on.
    public func sheetFieldFocused(_ field: EditorFieldID) {
        guard !isLocked(field), focus != .field(field) else { return }
        if let current = focus?.field {
            closePopups()
            blur(current)
        }
        refocusRequest = nil
        focus = .field(field)
        didFocus(field)
    }

    public func sheetFieldUnfocused(_ field: EditorFieldID) {
        guard focus == .field(field) else { return }
        closePopups()
        blur(field)
        refocusRequest = nil
        if focus == .field(field) { focus = nil }
    }

    public func sheetTextChanged(_ field: EditorFieldID, to newText: String) {
        guard !isLocked(field) else { return }
        texts[field] = newText
        fieldSelection = NSRange(location: (newText as NSString).length, length: 0)
    }

    /// An amount without the keyboard takes its new sign at once.
    public func sheetSignToggled(_ field: EditorFieldID) {
        guard field.column == .amount, !isLocked(field), !hasOpenDialog else { return }
        takeTypedSign(field)
        chooseSign(field, inflow: !isInflow(field))
        guard focus != .field(field) else { return }
        commit(field, reason: .lostFocus)
        refocusRequest = nil
    }

    /// A sign typed at the start would win over the button on blur, so the button flips what it says.
    private func takeTypedSign(_ field: EditorFieldID) {
        let typed = text(field).trimmingCharacters(in: .whitespaces)
        guard let first = typed.first, Self.signs[first] != nil else { return }
        let amount = typedAmount(field)
        let isArithmetic = Calculator.evaluate(typed, formatter: formatter) != nil
        setText(field, isArithmetic ? formatter.registerAmount(abs(amount)) : String(typed.dropFirst()))
    }

    /// What a picker for the payee, category or account offers, narrowed by its search text.
    public func choices(for field: EditorFieldID, matching search: String) -> [DropDownItem] {
        guard let kind = dropDownKind(for: field) else { return [] }
        return DropDownMatching.filter(allItems(kind), kind: kind, text: search).filter { $0.kind != .prompt }
    }

    /// A searched payee the list does not know yet, offered as a new one.
    public func newPayeeChoice(_ search: String) -> String? {
        let typed = search.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, !Payee.isTransferPayeeName(typed),
            !allItems(.payee).contains(where: { $0.isEnabled && Payee.sameName($0.value, typed) })
        else { return nil }
        return typed
    }

    /// A picked row commits as a clicked list row does; nothing keeps the focus.
    public func choose(_ value: String, for field: EditorFieldID) {
        guard !isLocked(field), !hasOpenDialog else { return }
        if let current = focus?.field, current != field {
            closePopups()
            blur(current)
        }
        closePopups()
        focus = nil
        setText(field, value)
        commit(field, reason: .clickedItem(backward: false))
        refocusRequest = nil
    }

    public func addCategoryClicked(for field: EditorFieldID) {
        guard field.column == .category, !hasOpenDialog else { return }
        closePopups()
        pendingCategoryField = field
        addCategoryForm = AddCategoryForm(masterName: "", name: "")
    }

    /// Typing a date has the Mac's limits; the picker offers no other days.
    public var pickableDates: ClosedRange<DateWithoutTime> {
        let span = 10 * 365
        return (isScheduled ? today : today.addingDays(-span))...today.addingDays(span)
    }

    public func datePicked(_ date: DateWithoutTime) {
        guard !isLocked(.main(.date)) else { return }
        chooseDate(date)
    }

    @discardableResult
    public func addSplitLine() -> String {
        appendSubRow()
    }

    /// A new transaction can go to any account; an existing one moves only in Alle Konten, as on the Mac.
    public var choosesAccount: Bool { isAllAccounts || mode == .new }

    /// What the sheet shows for a field: a category without its group, a transfer by its other account.
    public func sheetValue(_ field: EditorFieldID) -> EditorSheetValue {
        let text = text(field)
        switch field.column {
        case .date where !field.isSub:
            return EditorSheetValue(text: formatter.dateLong(clone.date))
        case .payee where Payee.isTransferPayeeName(text):
            return EditorSheetValue(text: Payee.transferTargetAccountName(text) ?? text, isTransfer: true)
        case .category where !field.isSub && isSplitMode:
            return EditorSheetValue(text: Self.splitTitle(parts: subIds.count))
        case .category:
            return EditorSheetValue(text: budget.category(fullName: text)?.name ?? text)
        default:
            return EditorSheetValue(text: text)
        }
    }

    /// A transfer between two budget accounts needs no category, so the sheet leaves the row out.
    public var showsCategory: Bool {
        guard isOnBudget || isSplitMode else { return false }
        let payee = text(.main(.payee))
        guard Payee.isTransferPayeeName(payee),
            let target = Payee.transferTargetAccountName(payee).flatMap(budget.account(named:))
        else { return true }
        return !target.onBudget
    }

    public static func splitTitle(parts: Int) -> String { "Aufgeteilt (\(parts))" }

    /// A part's line in the sheet: its category and its signed amount.
    public func partSummary(_ id: String) -> EditorPartSummary {
        let category = sheetValue(.sub(id, .category)).text
        let amount = amount(of: id)
        return EditorPartSummary(
            category: category.isEmpty ? prompt(.sub(id, .category)) : category, hasCategory: !category.isEmpty,
            amount: amount == 0 ? "" : formatter.currency(amount), isInflow: amount > 0)
    }

    public var sheetTitle: String {
        switch (isScheduled, mode) {
        case (true, .new): RegisterScheduler.addTitle
        case (true, .existing): "Geplante Buchung"
        case (false, .new): RegisterViewModel.addTitle
        case (false, .existing): "Buchung"
        }
    }

    /// A transaction waiting for approval confirms with approving it.
    public var sheetConfirmButton: EditorButton {
        buttons.contains(.approve) ? .approve : prominentButton
    }

    /// Deleting has its own place at the sheet's end.
    public var sheetMoreButtons: [EditorButton] {
        buttons.filter { ![sheetConfirmButton, .cancel, .delete].contains($0) }
    }

    /// A stored transaction's status: waiting for approval, else gebucht, vorgemerkt or abgeglichen.
    public var sheetStatus: EditorSheetStatus? {
        guard mode == .existing, !isScheduled else { return nil }
        if needsApproval && !clone.approved { return .waiting }
        switch clone.cleared {
        case .uncleared: return .uncleared
        case .cleared: return .cleared
        case .reconciled: return .reconciled
        }
    }

    public func sheetStatusChosen(_ status: EditorSheetStatus) {
        let switchable: [EditorSheetStatus] = [.uncleared, .cleared]
        guard let current = sheetStatus, current != status, switchable.contains(current), switchable.contains(status)
        else { return }
        toggleCleared()
    }

    /// A stored transaction no other one leads can be deleted from its sheet.
    public var sheetDeletes: Bool { mode == .existing && !isScheduled && leader == nil }

    /// Swiping the sheet away would lose the changes.
    public var keepsSheet: Bool { hasChanges || hasEditedText }

    private var hasEditedText: Bool {
        texts.contains { field, text in
            guard field.column == .memo || field.column == .amount else { return false }
            let stored =
                field.isSub
                ? subText(field.column, of: clone.subtransactions.first { $0.id == field.subId })
                : originalText(field, of: clone)
            return text != stored
        }
    }
}

public struct EditorSheetValue: Hashable, Sendable {
    public var text: String
    public var isTransfer = false
}

public enum EditorSheetStatus: Hashable, Sendable {
    case waiting, uncleared, cleared, reconciled
}

public struct EditorPartSummary: Hashable, Sendable {
    public var category: String
    public var hasCategory: Bool
    public var amount: String
    public var isInflow: Bool
}

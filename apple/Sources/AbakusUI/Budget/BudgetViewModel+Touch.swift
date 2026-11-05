import AbakusCore
import Foundation

/// iPhone and iPad assign in a category's sheet instead of the Mac's cell drop-down.
extension BudgetViewModel {
    /// Opens the sheet for the month tapped, or else the month in focus.
    public func categoryTapped(_ categoryId: String, month: DateWithoutTime? = nil) {
        present(.category(month: (month ?? focusMonth).firstOfMonth, categoryId: categoryId))
    }

    /// A category's or a group's sheet, or the iPad's popover in its place.
    public var showsTouchCallout: Bool {
        switch presentedPopup {
        case .category, .editCategory: true
        default: false
        }
    }

    public var showsCategoryPopover: Bool {
        guard let touchLayout, touchLayout != .phone, case .category = presentedPopup else { return false }
        return callouts.availableForm != nil
    }

    public var showsTouchSheet: Bool { showsTouchCallout && !showsCategoryPopover }

    /// The phone's cover list is a sheet of its own; the iPad's a popover beside the cell, as the Mac's.
    public var showsCoverSheet: Bool {
        guard touchLayout == .phone, case .available = presentedPopup else { return false }
        return callouts.availableForm != nil
    }

    public var coverPopover: BudgetCellID? {
        guard let touchLayout, touchLayout != .phone, case .available(let month, let id) = presentedPopup,
            callouts.availableForm != nil
        else { return nil }
        return BudgetCellID(month: month, categoryId: id)
    }

    public func coverDismissed() {
        if case .available = presentedPopup { dismissPopup() }
    }

    public func touchSheetSwipedAway() {
        if showsTouchCallout { touchSheetDismissed() }
    }

    /// The sheet's Zugewiesen keeps what is typed here, so closing the sheet with the keyboard up saves it.
    public func sheetAssignedChanged(_ text: String, in cell: BudgetCellID) {
        guard sheetAssigned?.cell != cell || sheetAssigned?.text != text else { return }
        sheetAssigned = BudgetCellEdit(cell: cell, text: text)
        sheetAssignedError = nil
    }

    @discardableResult
    public func commitSheetAssigned() -> Bool {
        guard let edit = sheetAssigned else { return true }
        if let error = assign(edit.text, to: edit.cell) {
            sheetAssignedError = error
            sheetAssignedRefusals += 1
            announceRefusal(error)
            return false
        }
        sheetAssigned = nil
        return true
    }

    func dropSheetAssigned() {
        sheetAssigned = nil
        sheetAssignedError = nil
    }

    /// Swiping the sheet away closes it as its Close button does; a category just added is discarded.
    public func touchSheetDismissed() {
        if !commitSheetAssigned() { dropSheetAssigned() }
        if let form = callouts.category {
            if form.isNew || form.deletion != nil {
                callouts.categoryCancelled()
            } else {
                if form.target != nil && !callouts.saveOpenTarget() { callouts.targetCancelClicked() }
                callouts.categoryDone()
            }
        } else {
            dismissPopup()
        }
    }
}

extension BudgetViewModel {
    /// A row moved in the list, counted as SwiftUI's onMove counts, makes the Mac's drop.
    public func touchRowsMoved(from source: IndexSet, to destination: Int) {
        guard source.count == 1, let index = source.first,
            let command = groups.touchMoveCommand(from: index, to: destination)
        else { return }
        performDrop(command)
    }
}

extension [BudgetGroup] {
    /// A category joins the group it lands under; a group takes the place among the groups it lands at.
    func touchMoveCommand(from source: Int, to destination: Int) -> BudgetCommand? {
        let rows = visibleRows
        guard rows.indices.contains(source), (0...rows.count).contains(destination) else { return nil }
        let moved = rows[source]
        var after = rows
        after.remove(at: source)
        let position = destination > source ? destination - 1 : destination
        after.insert(moved, at: position)
        switch moved.kind {
        case .uncategorized:
            return nil
        case .master:
            guard let current = rows.filter({ $0.kind == .master }).firstIndex(of: moved) else { return nil }
            let target = after[..<position].count { $0.kind == .master }
            guard target != current else { return nil }
            return .moveCategoryGroup(groupId: moved.id, index: Self.index(target, from: current))
        case .sub:
            guard let header = after[..<position].lastIndex(where: { $0.kind != .sub }),
                after[header].kind == .master
            else { return nil }
            let groupId = after[header].id
            let target = position - header - 1
            guard groupId == moved.masterId else {
                return .moveCategory(categoryId: moved.id, toGroupId: groupId, index: target)
            }
            guard let current = first(where: { $0.id == groupId })?.subs.firstIndex(of: moved), target != current
            else { return nil }
            return .moveCategory(categoryId: moved.id, toGroupId: groupId, index: Self.index(target, from: current))
        }
    }

    /// The store counts the moved row's old place, as a drop line does.
    private static func index(_ target: Int, from current: Int) -> Int {
        target > current ? target + 1 : target
    }
}

public struct BudgetMonthPickerCell: Hashable, Sendable, Identifiable {
    public let month: DateWithoutTime
    public let label: String
    public let isPast: Bool
    public let isCurrent: Bool
    public let isShown: Bool

    public var id: DateWithoutTime { month }
}

public struct BudgetWaiting: Hashable, Sendable {
    public let overspentIds: [String]
    public let approvals: Int

    public var isEmpty: Bool { overspentIds.isEmpty && approvals == 0 }

    public var overspentText: String? {
        switch overspentIds.count {
        case 0: nil
        case 1: "1 Kategorie überzogen"
        case let count: "\(count) Kategorien überzogen"
        }
    }

    public var approvalsText: String? {
        approvals == 0 ? nil : RegisterViewModel.approvalsTitle(approvals)
    }
}

public struct BudgetAvailableBreakdown: Hashable, Sendable {
    public static let carriedLabel = "Übrig aus Vormonat"

    public let carried: String
    public let assignedLabel: String
    public let activityLabel: String
    public let activity: String
    public let available: String
    public let isOverspent: Bool
    public let marker: BudgetAvailableMarker?
}

extension BudgetViewModel {
    public static let uncategorizedSearch = "Ist: Nicht kategorisiert"

    public var shownMonthsTitle: String {
        shownMonths.first.map { formatter.monthHeader($0) } ?? ""
    }

    public func monthPickerCells(year: Int) -> [BudgetMonthPickerCell] {
        let current = today.firstOfMonth
        let shown = Set(shownMonths)
        return (1...12).map { number in
            let month = DateWithoutTime(year: year, month: number, day: 1)
            return BudgetMonthPickerCell(
                month: month, label: formatter.shortMonthName(number), isPast: month < current,
                isCurrent: month == current, isShown: shown.contains(month))
        }
    }

    public func todayClicked() {
        select(today.firstOfMonth)
    }

    public var showsTodaysMonth: Bool { shownMonths.first == today.firstOfMonth }

    /// Today's month while it is shown, else the first; the iPad names what waits for it.
    public var monthInFocus: BudgetMonth? { month(focusMonth) }

    public func waiting(in month: BudgetMonth) -> BudgetWaiting {
        let overspent = groups.flatMap(\.subs).filter { (month.category($0.id)?.balance ?? 0) < 0 }.map(\.id)
        return BudgetWaiting(overspentIds: overspent, approvals: store.budget.approvalCount)
    }

    /// Opens the first one's cover list; its group unfolds, as the iPad's popover needs the cell to stand on.
    public func overspentTapped(in month: BudgetMonth) {
        guard let id = waiting(in: month).overspentIds.first else { return }
        if let group = groups.first(where: { $0.subs.contains { $0.id == id } }), !group.isExpanded {
            perform(.setCategoryGroupExpanded(groupId: group.id, true))
        }
        balanceClicked(month: month.month, categoryId: id)
    }

    public func approvalsTapped() {
        onShowApprovals()
    }

    public func uncategorizedTapped() {
        onShowAllAccountsSearch(Self.uncategorizedSearch)
    }

    public func availableBreakdown(of categoryId: String, in date: DateWithoutTime) -> BudgetAvailableBreakdown? {
        guard let month = month(date), let figures = month.category(categoryId) else { return nil }
        let this = formatter.shortMonthName(date.month)
        return BudgetAvailableBreakdown(
            carried: formatter.currency(figures.balance - figures.assigned + figures.spent),
            assignedLabel: "Zugewiesen im \(this)", activityLabel: "Aktivität im \(this)",
            activity: formatter.currency(figures.outflows), available: formatter.currency(figures.balance),
            isOverspent: figures.isOverspent, marker: figures.availableMarker(isBeingBudgeted: month.isBeingBudgeted))
    }
}

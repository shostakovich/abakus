import AbakusCore
import CoreGraphics
import Foundation

public struct BudgetDrag: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case sub(categoryId: String, masterId: String)
        case master(String)
    }

    public let source: Source
    public let rowId: String
    public let start: CGPoint
    public let rowOrigin: CGFloat
    public internal(set) var location: CGPoint
    public internal(set) var isActive = false
    public internal(set) var target: BudgetDropTarget?
    public internal(set) var edgeDepth: CGFloat = 0

    public var proxyOffset: CGSize {
        CGSize(width: location.x - start.x, height: rowOrigin + location.y - start.y)
    }

    public var autoScrolls: Bool { isActive && edgeDepth != 0 }
}

/// A drop line is drawn only below a sub row.
public struct BudgetDropTarget: Hashable, Sendable {
    public let lineBelow: String?
    public let command: BudgetCommand
}

extension BudgetViewModel {
    public static let autoScrollTopBand: CGFloat = 200
    public static let autoScrollBottomBand: CGFloat = 100

    public func dragPressed(rowId: String, at point: CGPoint) {
        guard let source = dragSource(rowId), let top = groups.top(of: rowId) else { return }
        drag = BudgetDrag(source: source, rowId: rowId, start: point, rowOrigin: top - scrollOffset, location: point)
    }

    public func dragMoved(to point: CGPoint, edgeDepth: CGFloat = 0) {
        guard var current = drag else { return }
        current.location = point
        current.edgeDepth = edgeDepth
        if !current.isActive {
            let distance = max(abs(point.x - current.start.x), abs(point.y - current.start.y))
            guard distance > BudgetMetrics.dragThreshold else {
                drag = current
                return
            }
            current.isActive = true
            commitEdit()
            hoveredRowId = nil
        }
        drag = current
        dragTargetMayHaveChanged()
    }

    public func dragReleased() {
        guard let current = drag else { return }
        drag = nil
        guard current.isActive, let target = current.target else { return }
        do {
            try store.perform(target.command)
        } catch BudgetError.categoryNameTakenInGroup(let master, let name) {
            dialogs.show(Self.duplicateNamePrompt(master: master, name: name))
        } catch {}
    }

    /// A cancelled gesture never reports its end, so the drag would otherwise linger into the next one.
    public func dragCancelled() {
        drag = nil
    }

    static func duplicateNamePrompt(master: String, name: String) -> TaskDialog<MessageChoice> {
        TaskDialog(
            instruction: "",
            content: BudgetError.categoryNameTakenInGroup(group: master, name: name).errorDescription ?? "",
            buttons: [.init(.close, title: "OK", isDefault: true)], dismissal: .close)
    }

    /// (depth / 7)², and only while the pointer is inside a band.
    public func autoScrollTick() {
        guard let current = drag, current.autoScrolls else { return }
        let step = max(1, pow(abs(current.edgeDepth) / 7, 2))
        scroll(to: scrollOffset + (current.edgeDepth < 0 ? -step : step))
    }

    public static func autoScrollDepth(windowY: CGFloat, windowHeight: CGFloat) -> CGFloat {
        if windowY < autoScrollTopBand { return windowY - autoScrollTopBand }
        if windowY > windowHeight - autoScrollBottomBand { return windowY - (windowHeight - autoScrollBottomBand) }
        return 0
    }

    /// Only the category column's rows accept a drop.
    func dragTargetMayHaveChanged() {
        guard let current = drag, current.isActive else { return }
        let rows = CGRect(x: 0, y: 0, width: layout.categoryWidth, height: layout.viewportHeight)
        drag?.target =
            rows.contains(current.location)
            ? dropTarget(contentY: current.location.y + scrollOffset, source: current.source) : nil
    }

    private func dragSource(_ rowId: String) -> BudgetDrag.Source? {
        for group in groups where group.header.kind == .master {
            if group.id == rowId { return .master(rowId) }
            if group.subs.contains(where: { $0.id == rowId }) { return .sub(categoryId: rowId, masterId: group.id) }
        }
        return nil
    }

    func dropTarget(contentY: CGFloat, source: BudgetDrag.Source) -> BudgetDropTarget? {
        let groups = self.groups
        var groupTop: CGFloat = 0
        for (index, group) in groups.enumerated() {
            defer { groupTop += group.height }
            guard contentY >= groupTop, contentY < groupTop + group.height else { continue }
            guard group.header.kind == .master else { return nil }
            let rowIndex = Int((contentY - groupTop) / BudgetMetrics.rowHeight)
            let row = group.visibleRows[min(rowIndex, group.visibleRows.count - 1)]
            let isBottomHalf =
                (contentY - groupTop).truncatingRemainder(dividingBy: BudgetMetrics.rowHeight)
                >= BudgetMetrics.rowHeight / 2
            switch source {
            case .sub(let categoryId, let masterId):
                return subTarget(
                    categoryId, from: masterId, over: row, in: group, isBottomHalf: isBottomHalf,
                    previous: previousMaster(before: index, in: groups))
            case .master(let masterId):
                let isTopHalf = contentY - groupTop < group.height / 2
                return masterTarget(masterId, over: group, isTopHalf: isTopHalf, groupIndex: index, in: groups)
            }
        }
        return nil
    }

    private func previousMaster(before index: Int, in groups: [BudgetGroup]) -> BudgetGroup? {
        groups[..<index].last { $0.header.kind == .master }
    }

    /// A move into a master that already has the name shows no line; the store refuses it on release with the prompt.
    private func subTarget(
        _ categoryId: String, from sourceMaster: String, over row: BudgetCategoryRow, in group: BudgetGroup,
        isBottomHalf: Bool, previous: BudgetGroup?
    ) -> BudgetDropTarget? {
        let masterId: String
        let index: Int
        var lineBelow: String?
        if row.kind == .sub {
            guard row.id != categoryId, let rowIndex = group.subs.firstIndex(where: { $0.id == row.id }) else {
                return nil
            }
            (masterId, index) = (group.id, rowIndex + (isBottomHalf ? 1 : 0))
            lineBelow = isBottomHalf ? row.id : (rowIndex == 0 ? nil : group.subs[rowIndex - 1].id)
        } else if !isBottomHalf, let previous {
            (masterId, index) = (previous.id, previous.subs.count)
        } else {
            (masterId, index) = (group.id, 0)
        }
        let clashes = masterId != sourceMaster && master(masterId, hasSubNamedLike: categoryId)
        return BudgetDropTarget(
            lineBelow: clashes ? nil : lineBelow,
            command: .moveCategory(categoryId: categoryId, toGroupId: masterId, index: index))
    }

    private func masterTarget(
        _ masterId: String, over group: BudgetGroup, isTopHalf: Bool, groupIndex: Int, in groups: [BudgetGroup]
    ) -> BudgetDropTarget? {
        guard group.id != masterId else { return nil }
        let masters = groups.filter { $0.header.kind == .master }.map(\.id)
        guard let index = masters.firstIndex(of: group.id) else { return nil }
        if isTopHalf {
            return BudgetDropTarget(lineBelow: nil, command: .moveCategoryGroup(groupId: masterId, index: index))
        }
        let isLast = index + 1 == masters.count
        return BudgetDropTarget(
            lineBelow: isLast && group.isExpanded ? group.subs.last?.id : nil,
            command: .moveCategoryGroup(groupId: masterId, index: index + 1))
    }

    private func master(_ masterId: String, hasSubNamedLike categoryId: String) -> Bool {
        let budget = store.budget
        guard let name = budget.category(withId: categoryId)?.name.lowercased(),
            let master = budget.categoryGroup(withId: masterId)
        else { return false }
        return master.categories.contains { $0.id != categoryId && $0.name.lowercased() == name }
    }
}

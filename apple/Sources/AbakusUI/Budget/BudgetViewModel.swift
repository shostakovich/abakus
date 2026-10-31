import AbakusCore
import CoreGraphics
import Foundation
import Observation

public struct BudgetTimelineCell: Hashable, Sendable {
    public let month: Int
    public let label: String
    public let isShown: Bool
    public let isCurrent: Bool
    public let hasNoData: Bool
}

public enum BudgetHoverColumn: Hashable, Sendable {
    case categories
    case month(DateWithoutTime)
}

/// The row under the pointer and the column it is in: every column shows the row's fields, only that one its icons.
public struct BudgetHover: Hashable, Sendable {
    public let rowId: String
    public let column: BudgetHoverColumn
}

@MainActor
@Observable
public final class BudgetViewModel {
    public let store: any BudgetStoring
    public let navigation: NavigationState
    public let dialogs: DialogStack
    @ObservationIgnored let settings: BudgetViewSettings

    public internal(set) var firstMonth: DateWithoutTime
    public internal(set) var categoryWidth: CGFloat
    public internal(set) var isHeaderExpanded: Bool
    public var headerProgress: CGFloat
    public var panelSize = CGSize.zero {
        didSet {
            placeOpeningMonth()
            endEditOutsideShownMonths()
        }
    }
    var storedScrollOffset: CGFloat = 0
    public internal(set) var hover: BudgetHover?
    public internal(set) var presentedPopup: BudgetPopup?
    public internal(set) var editor: BudgetCellEdit?
    public internal(set) var quickBudget: BudgetQuickBudgetList?
    public internal(set) var calculator: BudgetCalculator?
    public internal(set) var drag: BudgetDrag?
    public internal(set) var panelFocusRequest = 0
    @ObservationIgnored public private(set) lazy var callouts = BudgetCalloutController(budget: self)
    @ObservationIgnored var hasPlacedOpeningMonth = false
    @ObservationIgnored var resizeOrigin: CGFloat?
    @ObservationIgnored var isAppModalOpen: () -> Bool = { false }
    @ObservationIgnored private var cache: (inputs: SheetInputs, sheet: BudgetSheet, groups: [BudgetGroup])?
    @ObservationIgnored private var formatterCache: (metaData: BudgetMetaData, formatter: BudgetFormatter)?
    @ObservationIgnored private var fittedWidthCache: (names: [BudgetCategoryFit], width: CGFloat)?

    init(store: any BudgetStoring, navigation: NavigationState, dialogs: DialogStack, settings: BudgetViewSettings) {
        self.store = store
        self.navigation = navigation
        self.dialogs = dialogs
        self.settings = settings
        firstMonth = settings.lastSelectedMonth ?? store.today().firstOfMonth
        categoryWidth = settings.categoryColumnWidth
        isHeaderExpanded = settings.isHeaderExpanded
        headerProgress = settings.isHeaderExpanded ? 1 : 0
    }

    public convenience init(store: any BudgetStoring, navigation: NavigationState, dialogs: DialogStack = DialogStack())
    {
        self.init(
            store: store, navigation: navigation, dialogs: dialogs, settings: BudgetViewSettings(budget: nil, app: nil))
    }

    var today: DateWithoutTime { store.today() }

    /// A task dialog or an app-modal UI such as Payee Settings keeps the keyboard and the clicks.
    public var isCoveredByModal: Bool { dialogs.isPresenting || isAppModalOpen() }

    public var takesKeyFocusBack: Bool { editor == nil && presentedPopup == nil && !isCoveredByModal }

    var formatter: BudgetFormatter {
        let metaData = store.budget.budgetMetaData
        if let formatterCache, formatterCache.metaData == metaData { return formatterCache.formatter }
        let formatter = BudgetFormatter(metaData: metaData)
        formatterCache = (metaData, formatter)
        return formatter
    }

    public var layout: BudgetLayout { layout(panelSize: panelSize) }

    func layout(panelSize: CGSize) -> BudgetLayout {
        var layout = columnLayout(panelSize: panelSize)
        let lineCounts = (0..<layout.columnCount).compactMap {
            month(firstMonth.addingMonths($0))?.headerLines(formatter: formatter).count
        }
        layout.headerLineCount = lineCounts.max() ?? layout.headerLineCount
        return layout
    }

    private func columnLayout(panelSize: CGSize) -> BudgetLayout {
        BudgetLayout(panelSize: panelSize, categoryWidth: shownCategoryWidth, headerProgress: headerProgress)
    }

    public var shownCategoryWidth: CGFloat {
        min(max(categoryWidth, fittedCategoryWidth), BudgetMetrics.categoryWidthRange.upperBound)
    }

    /// Fits every category name at rest, up to 220 pt.
    var fittedCategoryWidth: CGFloat {
        let names = store.budget.budgetCategoryGroups.flatMap { master in
            [BudgetCategoryFit(name: master.name, isMaster: true)]
                + master.categories.map { BudgetCategoryFit(name: $0.name, isMaster: false) }
        }
        if let fittedWidthCache, fittedWidthCache.names == names { return fittedWidthCache.width }
        let width = min(names.map(\.rowWidth).max() ?? 0, BudgetMetrics.maximumFittedCategoryWidth).rounded(.up)
        fittedWidthCache = (names, width)
        return width
    }

    public var columnCount: Int { columnLayout(panelSize: panelSize).columnCount }

    public var shownMonths: [DateWithoutTime] {
        (0..<columnCount).map { firstMonth.addingMonths($0) }
    }

    var focusMonth: DateWithoutTime {
        let current = today.firstOfMonth
        return shownMonths.contains(current) ? current : firstMonth
    }

    private struct SheetInputs: Equatable {
        var budget: Budget
        var today: DateWithoutTime
    }

    public var sheet: BudgetSheet {
        cached.sheet
    }

    public var groups: [BudgetGroup] { cached.groups }

    /// A sheet that already spans the shown months serves them unchanged.
    private var cached: (sheet: BudgetSheet, groups: [BudgetGroup]) {
        let inputs = SheetInputs(budget: store.budget, today: today)
        let needed = [firstMonth, firstMonth.addingMonths(max(columnCount, 1))]
        if let cache, cache.inputs == inputs, needed.allSatisfy({ cache.sheet.month($0) != nil }) {
            return (cache.sheet, cache.groups)
        }
        let sheet = inputs.budget.budgetSheet(today: inputs.today, including: needed)
        let groups = sheet.groups
        cache = (inputs, sheet, groups)
        return (sheet, groups)
    }

    public func month(_ date: DateWithoutTime) -> BudgetMonth? {
        sheet.month(date)
    }

    public var showsEmptyOutflowHelp: Bool {
        get { settings.showsEmptyOutflowHelp }
        set { settings.showsEmptyOutflowHelp = newValue }
    }

    private func endEditOutsideShownMonths() {
        if let editor, !shownMonths.contains(editor.cell.month) { commitEdit() }
    }

    private func placeOpeningMonth() {
        guard !hasPlacedOpeningMonth, columnCount > 0 else { return }
        hasPlacedOpeningMonth = true
        let current = today.firstOfMonth
        if firstMonth > current {
            firstMonth = current
        } else if current > firstMonth.addingMonths(columnCount - 1) {
            firstMonth = current.addingMonths(-(columnCount - 1))
        }
    }

    public func leave() {
        commitEdit()
        calculator = nil
        drag = nil
        dismissPopup()
        hover = nil
    }

    public var timelineYear: Int { firstMonth.year }

    public func timelineCells() -> [BudgetTimelineCell] {
        let year = timelineYear
        let start = firstMonth.month - 1
        let end = start + columnCount
        let now = today
        let firstData = (sheet.firstMonthWithData ?? now).firstOfMonth
        return (0..<12).map { index in
            let month = index + 1
            let isShown = index >= start && index < end
            return BudgetTimelineCell(
                month: month, label: formatter.shortMonthName(month), isShown: isShown,
                isCurrent: month == now.month && year == now.year,
                hasNoData: !isShown && DateWithoutTime(year: year, month: month, day: 1) < firstData)
        }
    }

    public func timelineMonthTitle(_ month: Int) -> String {
        "\(formatter.monthName(month)) \(timelineYear)"
    }

    public var showsTimelineEnd: Bool {
        firstMonth.month - 1 + columnCount > 11
    }

    public func timelineMonthClicked(_ month: Int) {
        select(DateWithoutTime(year: timelineYear, month: month, day: 1))
    }

    public func previousMonthClicked() {
        select(firstMonth.addingMonths(-1))
    }

    public func nextMonthClicked() {
        select(firstMonth.addingMonths(1))
    }

    public func select(_ month: DateWithoutTime) {
        commitEdit()
        calculator = nil
        firstMonth = month.firstOfMonth
        settings.lastSelectedMonth = firstMonth
    }

    public var isHeaderAnimating: Bool { headerProgress != (isHeaderExpanded ? 1 : 0) }

    public func toggleHeaderDetails() {
        guard !isHeaderAnimating else { return }
        isHeaderExpanded.toggle()
        settings.isHeaderExpanded = isHeaderExpanded
    }

    public var headerToggleToolTip: String {
        isHeaderExpanded ? "Rechnung ausblenden" : "Rechnung zeigen"
    }

    public func beginColumnResize(atX x: CGFloat) {
        resizeOrigin = x
    }

    public func columnResizeMoved(toX x: CGFloat) {
        guard let origin = resizeOrigin else { return }
        let lower = max(BudgetMetrics.categoryWidthRange.lowerBound, fittedCategoryWidth)
        let upper = BudgetMetrics.categoryWidthRange.upperBound
        categoryWidth = min(max(shownCategoryWidth + x - origin, lower), upper)
        if categoryWidth > lower && categoryWidth < upper { resizeOrigin = x }
        endEditOutsideShownMonths()
    }

    public func endColumnResize() {
        guard resizeOrigin != nil else { return }
        resizeOrigin = nil
        settings.categoryColumnWidth = categoryWidth
    }

    public var hoveredRow: String? { hover?.rowId }

    public func rowHovered(_ rowId: String, in column: BudgetHoverColumn, _ inside: Bool) {
        let entered = BudgetHover(rowId: rowId, column: column)
        if inside {
            guard drag == nil, rowId != EntityID.uncategorizedMasterCategory else { return }
            hover = entered
        } else if hover == entered {
            hover = nil
        }
    }

    public func isPointerOver(_ rowId: String, in column: BudgetHoverColumn) -> Bool {
        hover == BudgetHover(rowId: rowId, column: column)
    }

    public var contentHeight: CGFloat { groups.contentHeight }

    public var maxScrollOffset: CGFloat { max(0, contentHeight - layout.viewportHeight) }

    public var scrollOffset: CGFloat { min(storedScrollOffset, maxScrollOffset) }

    public func scroll(to offset: CGFloat) {
        storedScrollOffset = min(max(0, offset), maxScrollOffset)
        if drag != nil { dragTargetMayHaveChanged() }
    }

    public func pageScroll(down: Bool) {
        scroll(to: scrollOffset + (down ? BudgetMetrics.pageScroll : -BudgetMetrics.pageScroll))
    }

    func reveal(_ rowId: String) {
        guard let top = groups.top(of: rowId) else { return }
        let viewport = layout.viewportHeight
        if top < scrollOffset {
            scroll(to: top)
        } else if top + BudgetMetrics.rowHeight > scrollOffset + viewport {
            scroll(to: top + BudgetMetrics.rowHeight - viewport)
        }
    }

    public func disclosureClicked(_ masterId: String) {
        guard let group = groups.first(where: { $0.id == masterId }), group.header.kind == .master else { return }
        perform(.setCategoryGroupExpanded(groupId: masterId, !group.isExpanded))
    }

    public func expandAllClicked() {
        perform(.setAllCategoryGroupsExpanded(true))
    }

    public func collapseAllClicked() {
        perform(.setAllCategoryGroupsExpanded(false))
    }

    func perform(_ command: BudgetCommand) {
        commitEdit()
        do {
            try store.perform(command)
        } catch let error as BudgetError {
            dialogs.show(.message(error.dialogInstruction, error.dialogContent ?? ""))
        } catch {
            dialogs.show(.message(error.localizedDescription, ""))
        }
    }

    public var popupAnchor: BudgetPopupAnchor? { presentedPopup?.anchor }

    public func present(_ popup: BudgetPopup) {
        open { $0.open(popup) }
    }

    /// Adding a category shows the new row's callout.
    public func addMasterCategoryClicked() {
        open { $0.addCategoryGroup() }
    }

    public func addSubCategoryClicked(masterId: String) {
        open { $0.addCategory(groupId: masterId) }
    }

    private func open(_ callout: (BudgetCalloutController) -> BudgetPopup?) {
        commitEdit()
        calculator = nil
        presentedPopup = callout(callouts)
    }

    public func dismissPopup() {
        presentedPopup = nil
        callouts.reset()
    }

    public func subOutflowsClicked(month: DateWithoutTime, categoryId: String) {
        guard let figures = self.month(month)?.category(categoryId) else { return }
        if figures.hasTransactions {
            present(.outflowSummary(month: month, source: .category(categoryId)))
        } else if showsEmptyOutflowHelp {
            present(.outflowHelp(month: month, categoryId: categoryId))
        }
    }

    public func masterOutflowsClicked(month: DateWithoutTime, masterId: String) {
        guard let figures = self.month(month)?.master(masterId) else { return }
        if figures.hasTransactions {
            present(.outflowSummary(month: month, source: .masterCategory(masterId)))
        } else if showsEmptyOutflowHelp {
            present(.outflowHelp(month: month, categoryId: masterId))
        }
    }

    public func balanceClicked(month: DateWithoutTime, categoryId: String) {
        present(.available(month: month, categoryId: categoryId))
    }

    public func totalsOutflowsClicked(month: DateWithoutTime) {
        guard self.month(month)?.hasTransactions == true else { return }
        present(.outflowSummary(month: month, source: .allOutflows))
    }
}

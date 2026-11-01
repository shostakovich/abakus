import AbakusCore
import CoreGraphics
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct BudgetViewModelTests {
    typealias F = BudgetScreenFixture

    @Test func theCurrentMonthOpensFirstWithoutASavedMonth() {
        let model = F().model().model
        #expect(model.firstMonth == day("2026-10-01"))
        #expect(model.shownMonths == [day("2026-10-01"), day("2026-11-01"), day("2026-12-01")])
        #expect(model.scrollOffset == 0)
        #expect(model.editor == nil)
    }

    @Test(arguments: [
        ("2026-07", "2026-08-01"), ("2026-09", "2026-09-01"), ("2026-12", "2026-10-01"), ("2025-01", "2026-08-01"),
    ])
    func theSavedMonthKeepsTheCurrentMonthInView(saved: String, first: String) {
        let storage = MemorySettingsStorage()
        storage.set(saved, forKey: "lastSelectedMonth|Budget")
        #expect(F().model(storage: storage).model.firstMonth == day(first))
    }

    @Test func choosingAMonthRemembersIt() {
        let storage = MemorySettingsStorage()
        let model = F().model(storage: storage).model
        model.timelineMonthClicked(5)
        #expect(model.firstMonth == day("2026-05-01"))
        model.previousMonthClicked()
        model.previousMonthClicked()
        model.previousMonthClicked()
        model.previousMonthClicked()
        model.previousMonthClicked()
        #expect(model.firstMonth == day("2025-12-01"))
        #expect(model.timelineYear == 2025)
        model.nextMonthClicked()
        #expect(storage.string(forKey: "lastSelectedMonth|Budget") == "2026-01")
        #expect(F().model(storage: storage).model.firstMonth == day("2026-08-01"))
    }

    @Test func choosingAMonthTheSheetAlreadySpansKeepsTheSheet() {
        let (model, store) = F().model()
        let range = model.sheet.months.map(\.month)
        model.select(day("2030-05-01"))
        #expect(model.sheet.month(day("2030-05-01")) != nil)
        let wide = model.sheet.months.count
        model.select(day("2026-11-01"))
        #expect(model.sheet.months.count == wide)
        try? store.perform(.setAssigned(month: day("2026-11-01"), categoryId: F.kino, amount: 7))
        #expect(model.sheet.months.map(\.month) == range)
        #expect(model.month(day("2026-11-01"))?.category(F.kino)?.assigned == 7)
    }

    @Test func theTimelineMarksShownCurrentAndEmptyMonths() {
        var fixture = F()
        fixture.budget(20, F.kino, in: "2026-08-01")
        let model = fixture.model().model
        let cells = model.timelineCells()
        #expect(
            cells.map(\.label) == ["Jan", "Feb", "Mrz", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"])
        #expect(cells.filter(\.isShown).map(\.month) == [10, 11, 12])
        #expect(cells.filter(\.isCurrent).map(\.month) == [10])
        #expect(cells.filter(\.hasNoData).map(\.month) == [1, 2, 3, 4, 5, 6, 7])
        #expect(model.showsTimelineEnd)
        #expect(model.timelineMonthTitle(3) == "März 2026")
        model.timelineMonthClicked(1)
        let january = model.timelineCells()
        #expect(january.filter(\.isShown).map(\.month) == [1, 2, 3])
        #expect(january[9].isCurrent && !january[9].isShown)
        #expect(!model.showsTimelineEnd)
        model.previousMonthClicked()
        #expect(model.timelineCells().allSatisfy { !$0.isCurrent })
    }

    @Test func onlyMonthsOfTheFirstShownYearLightUp() {
        let model = F().model().model
        model.timelineMonthClicked(11)
        #expect(model.timelineCells().filter(\.isShown).map(\.month) == [11, 12])
        #expect(model.shownMonths.last == day("2027-01-01"))
    }

    @Test func theColumnCountFollowsThePanel() {
        let model = F().model(panel: CGSize(width: 776, height: 600)).model
        #expect(model.shownMonths.count == 2)
        model.panelSize = CGSize(width: 1652, height: 600)
        #expect(model.shownMonths.count == 5)
        #expect(model.firstMonth == day("2026-10-01"))
    }

    @Test func theCalculationStartsClosedTogglesAppWideAndWaitsForTheAnimation() {
        let storage = MemorySettingsStorage()
        let model = F().model(storage: storage).model
        #expect(!model.isHeaderExpanded)
        #expect(model.layout.headerHeight == BudgetMetrics.monthHeaderHeight)
        #expect(model.headerToggleToolTip == "Rechnung zeigen")
        model.toggleHeaderDetails()
        #expect(model.isHeaderExpanded)
        #expect(storage.string(forKey: "budgetHeaderExpanded") == "true")
        model.toggleHeaderDetails()
        #expect(model.isHeaderExpanded)
        model.headerProgress = 1
        #expect(model.headerToggleToolTip == "Rechnung ausblenden")
        let relaunched = F().model(storage: storage).model
        #expect(relaunched.isHeaderExpanded)
        #expect(
            relaunched.layout.headerHeight == BudgetMetrics.monthHeaderHeight + relaunched.layout.headerDetailsHeight)
    }

    @Test func everyMonthHeaderGrowsToTheShownMonthWithTheMostHeaderLines() {
        var fixture = F()
        let model = fixture.model().model
        model.headerProgress = 1
        #expect(model.layout.headerHeight == 170)
        fixture.budget(100, F.kino, in: "2026-11-01")
        let ahead = fixture.model().model
        ahead.headerProgress = 1
        let lines = ahead.month(day("2026-10-01"))?.headerLines(formatter: ahead.formatter).map(\.text)
        #expect(lines?.suffix(2) == ["Für spätere Monate", "Nicht gedeckt im Nov"])
        #expect(ahead.layout.headerLineCount == 6)
        #expect(ahead.layout.headerHeight == 170 + 2 * BudgetMetrics.headerLineHeight)
    }

    @Test func theCategoryColumnResizesBetween190And380() {
        let storage = MemorySettingsStorage()
        let model = F().model(storage: storage).model
        model.beginColumnResize(atX: 100)
        model.columnResizeMoved(toX: 150)
        #expect(model.categoryWidth == 240)
        model.columnResizeMoved(toX: 400)
        #expect(model.categoryWidth == 380)
        model.columnResizeMoved(toX: 160)
        #expect(model.categoryWidth == 380)
        model.columnResizeMoved(toX: 140)
        #expect(model.categoryWidth == 370)
        model.columnResizeMoved(toX: -200)
        #expect(model.categoryWidth == 190)
        model.columnResizeMoved(toX: 150)
        #expect(model.categoryWidth == 200)
        model.endColumnResize()
        #expect(F().model(storage: storage).model.categoryWidth == 200)
    }

    @Test func theCategoryColumnFitsTheLongestNameUpTo220() throws {
        var fixture = F()
        let index = try #require(fixture.budget.categoryGroups.firstIndex { $0.id == F.sparen })
        fixture.budget.categoryGroups[index].name = "Regelmäßige Ausgaben"
        let model = fixture.model().model
        let fitted = 30 + ThemeFont.tableEmphasized.width(of: "Regelmäßige Ausgaben") + 8
        #expect(model.categoryWidth == 190)
        #expect(model.shownCategoryWidth == fitted.rounded(.up))
        #expect(model.layout.categoryWidth == model.shownCategoryWidth)
        model.beginColumnResize(atX: 100)
        model.columnResizeMoved(toX: 50)
        #expect(model.categoryWidth == fitted.rounded(.up))
        model.columnResizeMoved(toX: 130)
        #expect(model.categoryWidth == fitted.rounded(.up) + 30)
        fixture.budget.categoryGroups[index].name = String(repeating: "Regelmäßige Ausgaben ", count: 3)
        #expect(fixture.model().model.shownCategoryWidth == 220)
    }

    @Test func withoutAStoredWidthTheColumnIs190() {
        let storage = MemorySettingsStorage()
        #expect(F().model(storage: storage).model.categoryWidth == 190)
        storage.set("500", forKey: "categoryColumnWidth|Budget")
        #expect(F().model(storage: storage).model.categoryWidth == 380)
    }

    @Test func rowsListUncategorizedAndTheMasters() throws {
        var fixture = F()
        fixture.spend(7, nil, on: "2026-10-05")
        try fixture.budget.apply(.setCategoryGroupExpanded(groupId: F.sparen, false))
        let model = fixture.model().model
        #expect(model.groups.map(\.id) == [EntityID.uncategorizedMasterCategory, F.alltag, F.sparen, F.freizeit])
        #expect(
            model.groups.visibleRows.map(\.id) == [
                EntityID.uncategorizedMasterCategory, F.alltag, F.lebensmittel, F.kleidung, F.sparen, F.freizeit,
                F.kino,
            ])
        #expect(model.contentHeight == 224)
        #expect(model.groups[1].header.nameToolTip == "Alltag\n\nKlicken zum Umbenennen oder Löschen.")
    }

    @Test func masterTogglesAndExpandAllGoThroughTheStore() {
        let (model, store) = F().model()
        model.disclosureClicked(F.sparen)
        model.collapseAllClicked()
        model.expandAllClicked()
        #expect(
            store.commands == [
                .setCategoryGroupExpanded(groupId: F.sparen, false), .setAllCategoryGroupsExpanded(false),
                .setAllCategoryGroupsExpanded(true),
            ])
    }

    @Test func hoverShowsARowsIconsUntilThePointerLeavesIt() {
        let model = F().model().model
        model.rowHovered(F.kino, true)
        #expect(model.hoveredRowId == F.kino)
        model.rowHovered(F.alltag, true)
        model.rowHovered(F.kino, false)
        #expect(model.hoveredRowId == F.alltag)
        model.rowHovered(F.alltag, false)
        #expect(model.hoveredRowId == nil)
        model.rowHovered(EntityID.uncategorizedMasterCategory, true)
        #expect(model.hoveredRowId == nil)
    }

    @Test func hoverMarksOnlyTheAssignedCellUnderThePointer() {
        let model = F().model().model
        let november = BudgetCellID(month: day("2026-11-01"), categoryId: F.kino)
        let december = BudgetCellID(month: day("2026-12-01"), categoryId: F.kino)
        model.assignedCellHovered(november, true)
        #expect(model.hoveredAssignedCell == november)
        model.assignedCellHovered(december, true)
        model.assignedCellHovered(november, false)
        #expect(model.hoveredAssignedCell == december)
        model.assignedCellHovered(december, false)
        #expect(model.hoveredAssignedCell == nil)
    }

    @Test func scrollingStaysWithinTheRowsAndPagesBy100() {
        let model = F().model(panel: CGSize(width: 1076, height: 264)).model
        #expect(model.layout.viewportHeight == 135)
        #expect(model.contentHeight == 224)
        #expect(model.maxScrollOffset == 89)
        model.scroll(to: 500)
        #expect(model.scrollOffset == 89)
        model.collapseAllClicked()
        #expect(model.scrollOffset == 0)
        model.expandAllClicked()
        model.scroll(to: 0)
        model.panelSize = CGSize(width: 1076, height: 164)
        model.pageScroll(down: true)
        #expect(model.scrollOffset == 100)
        model.pageScroll(down: false)
        #expect(model.scrollOffset == 0)
        model.scroll(to: -10)
        #expect(model.scrollOffset == 0)
    }

    @Test func outflowClicksAskForTheSummaryOrTheHelp() {
        var fixture = F()
        fixture.spend(30, F.lebensmittel, on: "2026-10-03")
        let model = fixture.model().model
        let october = day("2026-10-01")
        model.subOutflowsClicked(month: october, categoryId: F.lebensmittel)
        #expect(model.presentedPopup == .outflowSummary(month: october, source: .category(F.lebensmittel)))
        #expect(model.popupAnchor == .outflows(october, F.lebensmittel))
        model.subOutflowsClicked(month: october, categoryId: F.kleidung)
        #expect(model.presentedPopup == .outflowHelp(month: october, categoryId: F.kleidung))
        model.masterOutflowsClicked(month: october, masterId: F.alltag)
        #expect(model.presentedPopup == .outflowSummary(month: october, source: .masterCategory(F.alltag)))
        model.dismissPopup()
        model.masterOutflowsClicked(month: october, masterId: EntityID.uncategorizedMasterCategory)
        #expect(model.presentedPopup == nil)
        model.totalsOutflowsClicked(month: day("2026-11-01"))
        #expect(model.presentedPopup == nil)
        model.totalsOutflowsClicked(month: october)
        #expect(model.presentedPopup == .outflowSummary(month: october, source: .allOutflows))
        model.showsEmptyOutflowHelp = false
        model.dismissPopup()
        model.subOutflowsClicked(month: october, categoryId: F.kleidung)
        #expect(model.presentedPopup == nil)
    }

    @Test func presentingAPopupCommitsTheEditedCell() {
        let (model, store) = F().model()
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("12")
        model.present(.incomeSummary(month: day("2026-10-01")))
        #expect(model.editor == nil)
        #expect(store.commands == [.setAssigned(month: day("2026-10-01"), categoryId: F.kino, amount: 12)])
        #expect(model.popupAnchor == .incomeLine(day("2026-10-01")))
    }

    @Test func everyPopupNamesTheControlItPointsAt() {
        let october = day("2026-10-01")
        let anchors: [(BudgetPopup, BudgetPopupAnchor)] = [
            (.monthQuickBudget(month: october), .monthQuickBudget(october)),
            (.editCategory(categoryId: F.kino), .categoryRow(F.kino)),
            (.incomeSummary(month: october), .incomeLine(october)),
            (.outflowSummary(month: october, source: .masterCategory(F.alltag)), .outflows(october, F.alltag)),
        ]
        for (popup, anchor) in anchors {
            #expect(popup.anchor == anchor)
        }
    }

    @Test func leavingTheScreenCommitsAndClosesEverything() {
        let (model, store) = F().model()
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("5")
        model.present(.incomeSummary(month: day("2026-10-01")))
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("6")
        model.leave()
        #expect(model.editor == nil)
        #expect(model.presentedPopup == nil)
        #expect(store.assignedCommands.count == 2)
    }
}

@MainActor
@Suite struct BudgetScreenNavigationTests {
    @Test func goToBudgetShowsItAndTheBudgetOpensWhereItWasLeft() {
        let storage = MemorySettingsStorage()
        let budget = BudgetScreenFixture().budget
        let first = AppModel(
            store: BudgetStore(budget: budget, today: { BudgetScreenFixture.today }), defaults: storage)
        #expect(first.navigation.selection == .account(BudgetScreenFixture.giro))
        first.goToBudget()
        #expect(first.navigation.selection == .budget)
        let second = AppModel(
            store: BudgetStore(budget: budget, today: { BudgetScreenFixture.today }), defaults: storage)
        #expect(second.navigation.selection == .budget)
        second.goToAccounts()
        let third = AppModel(
            store: BudgetStore(budget: budget, today: { BudgetScreenFixture.today }), defaults: storage)
        #expect(third.navigation.selection == .account(BudgetScreenFixture.giro))
    }

    @Test func switchingAwayCommitsTheEditedCell() {
        let model = AppModel(
            store: BudgetStore(budget: BudgetScreenFixture().budget, today: { BudgetScreenFixture.today }),
            selection: .budget, defaults: nil)
        model.budget.panelSize = BudgetScreenFixture.panel
        model.budget.beginEdit(model.budget.cell(BudgetScreenFixture.kino))
        model.budget.cellTextChanged("40")
        model.goToAccounts()
        #expect(model.budget.editor == nil)
        #expect(model.store.budget.assigned(in: day("2026-10-01"), categoryId: BudgetScreenFixture.kino) == 40)
    }

    @Test func theBudgetStepsBackWhileAnAppModalUIIsOpen() throws {
        let model = AppModel(
            store: BudgetStore(budget: BudgetScreenFixture().budget, today: { BudgetScreenFixture.today }),
            selection: .budget, defaults: nil)
        let budget = model.budget
        budget.panelSize = BudgetScreenFixture.panel
        budget.present(.editCategory(categoryId: BudgetScreenFixture.kino))
        model.openPayeeSettings(payeeName: nil)
        #expect(budget.isCoveredByModal)
        #expect(!budget.callouts.escapePressed())
        budget.callouts.mouseDownOutside()
        #expect(budget.presentedPopup == .editCategory(categoryId: BudgetScreenFixture.kino))
        try #require(model.payeeSettings).onClose(nil)
        #expect(!budget.isCoveredByModal)
        budget.dismissPopup()
        budget.beginEdit(budget.cell(BudgetScreenFixture.kino))
        model.openPayeeSettings(payeeName: nil)
        budget.mouseDown(at: .zero)
        #expect(budget.editor != nil)
        #expect(!budget.takesKeyFocusBack)
    }
}

@MainActor
@Suite struct BudgetViewSettingsTests {
    @Test func settingsAreKeptPerBudgetAndTheHeaderAppWide() {
        let storage = MemorySettingsStorage()
        let first = BudgetViewSettings(budget: BudgetSettings(storage: storage, budgetKey: "A"), app: storage)
        let second = BudgetViewSettings(budget: BudgetSettings(storage: storage, budgetKey: "B"), app: storage)
        first.lastSelectedMonth = day("2023-05-01")
        first.categoryColumnWidth = 250
        first.showsEmptyOutflowHelp = false
        first.opensOnBudget = true
        first.isHeaderExpanded = false
        #expect(storage.string(forKey: "lastSelectedMonth|A") == "2023-05")
        #expect(storage.string(forKey: "showEmptyOutflowTooltip|A") == "false")
        #expect(storage.string(forKey: "lastTabShown|A") == "Budget")
        #expect(second.lastSelectedMonth == nil)
        #expect(second.categoryColumnWidth == 190)
        #expect(second.showsEmptyOutflowHelp)
        #expect(!second.opensOnBudget)
        #expect(!second.isHeaderExpanded)
    }

    @Test func withoutStorageTheSettingsLastForTheSession() {
        let settings = BudgetViewSettings(budget: nil, app: nil)
        settings.categoryColumnWidth = 300
        settings.isHeaderExpanded = false
        #expect(settings.categoryColumnWidth == 300)
        #expect(!settings.isHeaderExpanded)
        #expect(settings.lastSelectedMonth == nil)
    }
}

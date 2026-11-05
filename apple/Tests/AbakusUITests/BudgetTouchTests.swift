import AbakusCore
import CoreGraphics
import Foundation
import Testing

@testable import AbakusUI

@Suite struct BudgetTouchLayoutTests {
    @Test(arguments: [CGFloat(375), 744, 1366])
    func aCompactWidthGivesThePhoneLayoutWithOneMonth(width: CGFloat) {
        let layout = BudgetTouchLayout(isCompact: true, width: width)
        #expect(layout == .phone)
        #expect(layout.monthCount == 1)
    }

    @Test(arguments: [
        (CGFloat(744), 1, CGFloat(224)), (799, 1, 224), (800, 2, 224), (813, 2, 224), (1109, 2, 243),
        (1110, 3, 244), (1366, 3, 300), (1600, 3, 320),
    ])
    func aRegularWidthGivesTheMonthsOfTheWidthRules(width: CGFloat, months: Int, category: CGFloat) {
        let layout = BudgetTouchLayout(isCompact: false, width: width)
        #expect(layout == .wide(months: months, categoryWidth: category))
        #expect(layout.monthCount == months)
    }

    @Test(arguments: [CGFloat(424), 440, 527])
    func aRegularWidthTooNarrowForAMonthGivesThePhoneLayout(width: CGFloat) {
        #expect(BudgetTouchLayout(isCompact: false, width: width) == .phone)
    }

    @Test func aRegularWidthWithRoomForOneMonthGivesTheWideLayout() {
        #expect(BudgetTouchLayout(isCompact: false, width: 528) == .wide(months: 1, categoryWidth: 224))
    }

    @Test func twoMonthsStartAt800PointsWhateverFits() {
        #expect(BudgetTouchLayout(isCompact: false, width: 799, minimumMonthWidth: 200).monthCount == 1)
        #expect(BudgetTouchLayout(isCompact: false, width: 800, minimumMonthWidth: 200).monthCount == 2)
    }

    @Test func largerTextGivesFewerMonths() {
        let layout = BudgetTouchLayout(isCompact: false, width: 1110, minimumMonthWidth: 300)
        #expect(layout == .wide(months: 2, categoryWidth: 244))
        #expect(BudgetTouchLayout(isCompact: false, width: 744, minimumMonthWidth: 500) == .phone)
    }
}

@MainActor
@Suite struct BudgetTouchTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    /// 100,00 income, Kino −25,00 and Kleidung 60,00 Verfügbar in October.
    private func model() -> BudgetViewModel {
        var fixture = F()
        fixture.spend(-100, F.readyToAssign, on: "2026-10-01")
        fixture.spend(25, F.kino, on: "2026-10-10")
        fixture.budget(60, F.kleidung, in: "2026-10-01")
        return fixture.model(panel: .zero).model
    }

    @Test func turningTheIPadMiniToLandscapeShowsThreeMonths() {
        let model = model()
        model.touchLayout = BudgetTouchLayout(isCompact: false, width: 744)
        #expect(model.shownMonths == [october])
        model.touchLayout = BudgetTouchLayout(isCompact: false, width: 1133)
        #expect(model.shownMonths == [october, day("2026-11-01"), day("2026-12-01")])
    }

    @Test func thePhoneShowsOneMonthWhateverTheMacPanelWouldShow() {
        let model = model()
        model.touchLayout = .phone
        model.panelSize = F.panel
        #expect(model.shownMonths == [october])
        model.nextMonthClicked()
        #expect(model.shownMonths == [day("2026-11-01")])
    }

    @Test func tappingACategoryOpensItsSheetWithoutTheCoverList() throws {
        let model = model()
        model.touchLayout = .phone
        model.categoryTapped(F.kino)
        #expect(model.presentedPopup == .category(month: october, categoryId: F.kino))
        #expect(model.callouts.category?.name == "Kino")
        #expect(try #require(model.callouts.availableForm).isOverspent)
        #expect(model.showsTouchSheet)
        #expect(!model.showsCoverSheet)
    }

    @Test func onThePhoneAnOverspentVerfuegbarOpensOnlyTheCoverListInASheet() {
        let model = model()
        model.touchLayout = .phone
        model.balanceClicked(month: october, categoryId: F.kino)
        #expect(model.showsCoverSheet)
        #expect(!model.showsTouchSheet)
        #expect(model.coverPopover == nil)
        #expect(model.callouts.coverTitle == "25,00\u{00A0}€ decken aus")
        model.callouts.cover(from: F.kleidung)
        #expect(model.presentedPopup == nil)
        #expect(!model.showsCoverSheet)
        #expect(model.month(october)?.category(F.kino)?.balance == 0)
        #expect(model.month(october)?.category(F.kleidung)?.balance == 35)
        #expect(model.undoNotice != nil)
    }

    @Test func onTheIPadAnOverspentVerfuegbarOpensTheCoverListBesideItsCell() {
        let model = model()
        model.touchLayout = .wide(months: 2, categoryWidth: 224)
        model.balanceClicked(month: october, categoryId: F.kino)
        #expect(model.coverPopover == model.cell(F.kino))
        #expect(!model.showsCoverSheet)
        #expect(!model.showsTouchCallout)
        model.coverDismissed()
        #expect(model.presentedPopup == nil)
    }

    @Test func theTitleRenamesInPlaceAndTheSheetStaysOpen() {
        let model = model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.callouts.categoryName = "👕 Kleidung"
        model.callouts.categoryNameSubmitted()
        #expect(model.store.budget.category(withId: F.kleidung)?.name == "👕 Kleidung")
        #expect(model.presentedPopup == .category(month: october, categoryId: F.kleidung))
        model.callouts.categoryName = "Lebensmittel"
        model.callouts.categoryNameSubmitted()
        #expect(model.dialogs.isPresenting)
        #expect(model.store.budget.category(withId: F.kleidung)?.name == "👕 Kleidung")
    }

    @Test func aWideMonthsVerfuegbarOpensTheSheetForThatMonth() {
        let model = model()
        model.touchLayout = BudgetTouchLayout(isCompact: false, width: 900)
        let november = day("2026-11-01")
        model.categoryTapped(F.kleidung, month: november)
        #expect(model.presentedPopup == .category(month: november, categoryId: F.kleidung))
        #expect(model.callouts.availableForm?.month == november)
        #expect(model.callouts.category?.month == november)
    }

    @Test func assigningInTheSheetKeepsItOpenAndUpdatesVerfuegbar() throws {
        let model = model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.assign("20", to: model.cell(F.kleidung))
        #expect(model.month(october)?.category(F.kleidung)?.assigned == 20)
        #expect(model.presentedPopup == .category(month: october, categoryId: F.kleidung))
        #expect(model.callouts.availableForm?.available == 20)
    }

    @Test func closingTheSheetSavesTheAmountBeingTyped() {
        let model = model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.sheetAssignedChanged("75", in: model.cell(F.kleidung))
        model.touchSheetDismissed()
        #expect(model.presentedPopup == nil)
        #expect(model.month(october)?.category(F.kleidung)?.assigned == 75)
    }

    @Test func closingTheSheetSavesTheTargetBeingEdited() {
        let model = model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.callouts.editTargetClicked()
        model.callouts.targetAmount = "150"
        model.touchSheetDismissed()
        #expect(model.presentedPopup == nil)
        #expect(model.store.budget.target(in: october, categoryId: F.kleidung) == .monthly(150, setAside: true))
    }

    @Test func closingTheSheetDropsATargetItCannotSave() {
        let model = model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.callouts.editTargetClicked()
        model.touchSheetDismissed()
        #expect(model.presentedPopup == nil)
        #expect(model.store.budget.target(in: october, categoryId: F.kleidung) == nil)
    }

    @Test func tappingAGroupOpensItsSheetWithoutVerfuegbar() {
        let model = model()
        model.touchLayout = .phone
        model.categoryTapped(F.alltag)
        #expect(model.callouts.category?.isMaster == true)
        #expect(model.callouts.availableForm == nil)
    }

    @Test func thePhoneShowsACategoryInASheetAndTheIPadInAPopover() {
        let model = model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        #expect(model.showsTouchSheet)
        #expect(!model.showsCategoryPopover)
        model.touchLayout = .wide(months: 2, categoryWidth: 224)
        #expect(!model.showsTouchSheet)
        #expect(model.showsCategoryPopover)
        #expect(model.showsTouchCallout)
        model.categoryTapped(F.alltag)
        #expect(model.showsTouchSheet)
        #expect(!model.showsCategoryPopover)
    }

    @Test func swipingTheSheetAwayClosesItAsItsCloseButtonDoes() {
        let model = model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.sheetAssignedChanged("75", in: model.cell(F.kleidung))
        model.touchSheetSwipedAway()
        #expect(!model.showsTouchCallout)
        #expect(model.month(october)?.category(F.kleidung)?.assigned == 75)
    }
}

@MainActor
@Suite struct BudgetTouchHeadTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    /// 100,00 income, Kino −25,00 and Kleidung 60,00 Verfügbar in October.
    private func model(_ change: (inout F) -> Void = { _ in }) -> BudgetViewModel {
        var fixture = F()
        fixture.spend(-100, F.readyToAssign, on: "2026-10-01")
        fixture.spend(25, F.kino, on: "2026-10-10")
        fixture.budget(60, F.kleidung, in: "2026-10-01")
        change(&fixture)
        let model = fixture.model(panel: .zero).model
        model.touchLayout = .phone
        return model
    }

    @Test func theTitleNamesTheFirstShownMonth() {
        let model = model()
        #expect(model.shownMonthsTitle == "Oktober 2026")
        model.touchLayout = BudgetTouchLayout(isCompact: false, width: 900)
        #expect(model.shownMonthsTitle == "Oktober 2026")
    }

    @Test func theMonthPickerMutesPastMonthsAndJumpsBackToToday() {
        let model = model()
        let cells = model.monthPickerCells(year: 2026)
        #expect(
            cells.map(\.label) == ["Jan", "Feb", "Mrz", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"])
        #expect(cells.filter(\.isPast).count == 9)
        #expect(cells.filter(\.isCurrent).map(\.month) == [october])
        #expect(cells.filter(\.isShown).map(\.month) == [october])
        model.select(day("2027-03-01"))
        #expect(model.shownMonthsTitle == "März 2027")
        #expect(!model.showsTodaysMonth)
        model.todayClicked()
        #expect(model.shownMonths == [october])
        #expect(model.showsTodaysMonth)
    }

    @Test func theMonthInFocusIsTodaysWhileItIsShownElseTheFirst() {
        let model = model()
        model.touchLayout = BudgetTouchLayout(isCompact: false, width: 900)
        model.select(day("2026-09-01"))
        #expect(model.monthInFocus?.month == october)
        model.select(day("2027-01-01"))
        #expect(model.monthInFocus?.month == day("2027-01-01"))
    }

    @Test func theCalculationSignsIncomeWheneverThereIsSome() throws {
        let model = model()
        let income = { (date: String) in
            model.month(day(date))?.headerLines(formatter: model.formatter, withUnit: true)[2].amount
        }
        #expect(income("2026-10-01") == "+100,00\u{00A0}€")
        #expect(income("2026-11-01") == "0,00\u{00A0}€")
    }

    @Test func whatWaitsNamesTheOverspentAndOpensThemOneByOne() throws {
        let model = model { $0.spend(10, F.notgroschen, on: "2026-10-11") }
        let month = try #require(model.month(october))
        let waiting = model.waiting(in: month)
        #expect(waiting.overspentIds == [F.notgroschen, F.kino])
        #expect(waiting.overspentText == "2 Kategorien überzogen")
        #expect(waiting.approvalsText == nil)
        model.touchLayout = .phone
        model.overspentTapped(in: month)
        #expect(model.presentedPopup == .available(month: october, categoryId: F.notgroschen))
        #expect(model.showsCoverSheet)
    }

    @Test func anOverspentCategoryInAFoldedGroupOpensWithItsGroupUnfolded() throws {
        let model = model()
        model.touchLayout = BudgetTouchLayout(isCompact: false, width: 900)
        model.disclosureClicked(F.freizeit)
        #expect(!model.groups.visibleRows.map(\.id).contains(F.kino))
        model.overspentTapped(in: try #require(model.monthInFocus))
        #expect(model.groups.visibleRows.map(\.id).contains(F.kino))
        #expect(model.coverPopover == model.cell(F.kino))
    }

    @Test func nothingWaitsWithoutOverspendingOrApprovals() throws {
        let model = model { $0.budget(25, F.kino, in: "2026-10-01") }
        #expect(model.waiting(in: try #require(model.month(october))).isEmpty)
    }

    @Test func theApprovalsAndUncategorizedOpenAlleKontenWithTheirSearch() {
        let model = model()
        var searches: [String] = []
        model.onShowAllAccountsSearch = { searches.append($0) }
        model.onShowApprovals = { searches.append("approvals") }
        model.approvalsTapped()
        model.uncategorizedTapped()
        #expect(searches == ["approvals", "Ist: Nicht kategorisiert"])
    }

    @Test func theAvailableBreakdownReadsFromTheCarriedToVerfuegbar() throws {
        let model = model {
            $0.budget(30, F.kleidung, in: "2026-11-01")
            $0.spend(50, F.kleidung, on: "2026-11-05")
        }
        let breakdown = try #require(model.availableBreakdown(of: F.kleidung, in: day("2026-11-01")))
        #expect(breakdown.carried == "60,00\u{00A0}€")
        #expect(breakdown.assignedLabel == "Zugewiesen im Nov")
        #expect(breakdown.activityLabel == "Aktivität im Nov")
        #expect(breakdown.activity == "−50,00\u{00A0}€")
        #expect(breakdown.available == "40,00\u{00A0}€")
        #expect(!breakdown.isOverspent)
    }

    @Test(arguments: [
        (Decimal(40), Decimal(0), false, 0.26, BudgetTargetBarState.underfunded),
        (150, 0, false, 1, .funded),
        (150, 150, false, 1, .funded),
        (150, 200, false, 1, .overspent),
        (40, 0, true, 0.26, .snoozed),
    ])
    func theTargetBarFillsByTheAssignedShareOfTheNeed(
        assigned: Decimal, spent: Decimal, snoozed: Bool, share: Double, state: BudgetTargetBarState
    ) throws {
        let model = model {
            let target = Target.monthly(150, setAside: false)
            try! $0.budget.apply(.setTarget(month: day("2026-10-01"), categoryId: F.lebensmittel, target: target))
            $0.budget(assigned, F.lebensmittel, in: "2026-10-01")
            if spent > 0 { $0.spend(spent, F.lebensmittel, on: "2026-10-12") }
            if snoozed {
                try! $0.budget.apply(.setTargetSnoozed(month: day("2026-10-01"), categoryId: F.lebensmittel, true))
            }
        }
        let month = try #require(model.month(october))
        let bar = try #require(model.subRowDisplay(F.lebensmittel, in: month).targetBar)
        #expect(bar.state == state)
        #expect(abs(bar.share - share) < 0.001)
        #expect((model.subRowDisplay(F.lebensmittel, in: month).barMarker == .funded) == (state == .funded))
        #expect(model.subRowDisplay(F.kleidung, in: month).targetBar == nil)
    }

    @Test func aGreenBarMarksItsCategoryAsFundedEvenWithNothingLeft() throws {
        let model = model {
            let target = Target.monthly(150, setAside: false)
            try! $0.budget.apply(.setTarget(month: day("2026-10-01"), categoryId: F.lebensmittel, target: target))
            $0.budget(150, F.lebensmittel, in: "2026-10-01")
            $0.spend(150, F.lebensmittel, on: "2026-10-12")
        }
        let row = model.subRowDisplay(F.lebensmittel, in: try #require(model.month(october)))
        #expect(row.marker == nil)
        #expect(row.barMarker == .funded)
        #expect(row.barAccessibilityValue == "0,00, Ziel erreicht")
    }
}

/// The list's rows: Alltag, Lebensmittel, Kleidung, Sparen, Notgroschen, Freizeit, Kino.
@MainActor
@Suite struct BudgetTouchMoveTests {
    typealias F = BudgetScreenFixture

    private func moved(
        _ rowId: String, before targetId: String?, fixture: F = F()
    ) -> (model: BudgetViewModel, store: SpyBudgetStore) {
        let (model, store) = fixture.model()
        let rows = model.groups.visibleRows.map(\.id)
        let source = rows.firstIndex(of: rowId)!
        let destination = targetId.flatMap(rows.firstIndex(of:)) ?? rows.count
        model.touchRowsMoved(from: IndexSet(integer: source), to: destination)
        return (model, store)
    }

    @Test func aCategoryMovesWithinItsGroup() {
        let (model, store) = moved(F.lebensmittel, before: F.sparen)
        #expect(store.commands == [.moveCategory(categoryId: F.lebensmittel, toGroupId: F.alltag, index: 2)])
        #expect(model.subIds(of: F.alltag) == [F.kleidung, F.lebensmittel])
        let up = moved(F.kleidung, before: F.lebensmittel).store
        #expect(up.commands == [.moveCategory(categoryId: F.kleidung, toGroupId: F.alltag, index: 0)])
    }

    @Test func aCategoryMovesIntoTheGroupAboveWhereItLands() {
        let (model, store) = moved(F.kino, before: F.kleidung)
        #expect(store.commands == [.moveCategory(categoryId: F.kino, toGroupId: F.alltag, index: 1)])
        #expect(model.subIds(of: F.alltag) == [F.lebensmittel, F.kino, F.kleidung])
        let first = moved(F.kino, before: F.notgroschen).store
        #expect(first.commands == [.moveCategory(categoryId: F.kino, toGroupId: F.sparen, index: 0)])
        let last = moved(F.lebensmittel, before: nil).store
        #expect(last.commands == [.moveCategory(categoryId: F.lebensmittel, toGroupId: F.freizeit, index: 1)])
    }

    @Test func aGroupMovesAmongTheGroups() {
        let up = moved(F.freizeit, before: F.alltag).store
        #expect(up.commands == [.moveCategoryGroup(groupId: F.freizeit, index: 0)])
        let down = moved(F.alltag, before: F.freizeit)
        #expect(down.store.commands == [.moveCategoryGroup(groupId: F.alltag, index: 2)])
        #expect(
            down.model.groups.map(\.id).filter { $0 != EntityID.uncategorizedMasterCategory } == [
                F.sparen, F.alltag, F.freizeit,
            ])
    }

    @Test func aMoveThatChangesNothingOrLandsAboveEveryGroupIsIgnored() {
        #expect(moved(F.kino, before: nil).store.commands.isEmpty)
        #expect(moved(F.lebensmittel, before: F.kleidung).store.commands.isEmpty)
        #expect(moved(F.alltag, before: F.kleidung).store.commands.isEmpty)
        #expect(moved(F.sparen, before: F.kleidung).store.commands.isEmpty)
        #expect(moved(F.kino, before: F.alltag).store.commands.isEmpty)
    }

    @Test func aMoveIntoAGroupThatHasTheNameShowsTheDuplicatePrompt() throws {
        var fixture = F()
        try fixture.budget.apply(.renameCategory(categoryId: F.kleidung, name: "kino"))
        let (model, store) = moved(F.kino, before: F.kleidung, fixture: fixture)
        #expect(store.budget.category(withId: F.kino)?.categoryGroupId == F.freizeit)
        #expect(model.dialogs.presented.last?.dialog.buttons.map(\.title) == ["OK"])
    }
}

extension BudgetViewModel {
    fileprivate func subIds(of groupId: String) -> [String]? {
        groups.first { $0.id == groupId }?.subs.map(\.id)
    }
}

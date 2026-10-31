import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterSearchTests {
    private func searchModel() -> (RegisterFixture, RegisterViewModel, [String: String]) {
        var fixture = RegisterFixture()
        var ids: [String: String] = [:]
        ids["rewe"] = fixture.add(fixture.giro, -40, payee: "REWE", category: fixture.groceries, memo: "Milch")
        ids["aral"] = fixture.add(fixture.giro, -60, on: "2014-05-12", payee: "Aral")
        ids["split"] = fixture.add(
            fixture.giro, -50, on: "2014-05-14", payee: "Kaufland", id: "SPLIT",
            subtransactions: [
                Subtransaction(id: "S1", transactionId: "SPLIT", amount: -30, memo: "Essen"),
                Subtransaction(id: "S2", transactionId: "SPLIT", amount: -20, memo: "Seife"),
            ])
        let (model, _) = fixture.spied()
        model.today = { day("2014-05-20") }
        return (fixture, model, ids)
    }

    @Test func typingShowsSuggestionsForTheCurrentTerm() {
        let (_, model, _) = searchModel()
        model.search.boxChanged("Empfänger: Ar")
        #expect(model.search.dropDown?.items.contains { $0.searchText == "Empfänger: Aral" } == true)
        model.search.boxChanged("Ausgang: 60, rew")
        #expect(model.search.dropDown?.items.contains { $0.searchText == "Empfänger: REWE" } == true)
        model.search.boxChanged("")
        #expect(model.search.dropDown == nil)
    }

    @Test func enterRunsTheTypedSearch() {
        let (_, model, ids) = searchModel()
        model.search.boxChanged("rewe")
        model.search.submitted()
        #expect(model.transactionIds == [ids["rewe"]!])
        #expect(model.search.info?.message == "1 Treffer für „rewe“")
        #expect(model.search.dropDown == nil)
    }

    @Test func aTypedCommaRunsTheSearch() {
        let (_, model, ids) = searchModel()
        model.search.boxChanged("Ausgang: 60")
        model.search.boxChanged("Ausgang: 60,")
        #expect(model.transactionIds == [ids["aral"]!])
        #expect(model.search.filter?.label == "Ausgang: 60")
    }

    @Test func pickingASuggestionReplacesTheTermAndSearches() throws {
        let (_, model, ids) = searchModel()
        model.search.boxChanged("Ausgang: 60, Ar")
        let index = try #require(model.search.dropDown?.items.firstIndex { $0.searchText == "Empfänger: Aral" })
        model.search.pickSuggestion(at: index)
        #expect(model.search.text == "Ausgang: 60, Empfänger: Aral, ")
        #expect(model.search.filter?.label == "Ausgang: 60, Empfänger: Aral")
        #expect(model.transactionIds == [ids["aral"]!])
    }

    @Test func arrowKeysMoveTheHighlightAndEnterPicksIt() {
        let (_, model, ids) = searchModel()
        model.search.boxChanged("Empfänger: Aral")
        let items = model.search.dropDown?.items ?? []
        let target = items.firstIndex { $0.searchText == "Empfänger: Aral" }!
        for _ in 0...target { model.search.moveHighlight(by: 1) }
        #expect(model.search.dropDown?.highlighted == target)
        model.search.submitted()
        #expect(model.transactionIds == [ids["aral"]!])
    }

    @Test func hintRowsCannotBePicked() {
        let (_, model, _) = searchModel()
        model.search.boxChanged("x")
        let hint = model.search.dropDown?.items.firstIndex { $0.prefix == "Dates" }
        model.search.pickSuggestion(at: hint ?? 0)
        #expect(model.search.filter == nil)
        #expect(model.search.text == "x")
    }

    @Test func unchangedTextDoesNotSearchAgain() {
        let (_, model, _) = searchModel()
        model.search.boxChanged("rewe")
        model.search.submitted()
        model.selectAll()
        model.search.boxChanged("rewe, ")
        model.search.submitted()
        #expect(model.selection.count == 1)
    }

    @Test func escapeEmptiesTheBoxThenCancelsTheDateFilter() {
        let (_, model, _) = searchModel()
        model.search.dateSelectorClicked()
        model.search.timeframePresetClicked(.thisMonth)
        model.search.boxChanged("rewe")
        model.search.submitted()
        model.search.escapePressed()
        #expect(model.search.text == "")
        #expect(model.search.filter == nil)
        #expect(model.search.dateFilter != nil)
        model.search.escapePressed()
        #expect(model.search.dateFilter == nil)
    }

    @Test func escapeFirstClosesTheDropDown() {
        let (_, model, _) = searchModel()
        model.search.boxChanged("rew")
        model.search.escapePressed()
        #expect(model.search.dropDown == nil)
        #expect(model.search.text == "rew")
    }

    @Test func leavingAnEmptyBoxEndsTheSearch() {
        let (_, model, _) = searchModel()
        model.search.boxChanged("rewe")
        model.search.submitted()
        model.search.focusChanged(true)
        model.search.boxChanged("")
        model.search.focusChanged(false)
        #expect(model.search.filter == nil)
    }

    @Test func emptyingTheBoxEndsTheSearchWithoutLeavingIt() {
        let (_, model, ids) = searchModel()
        model.search.boxChanged("rewe")
        model.search.submitted()
        model.search.boxChanged("")
        #expect(model.search.filter == nil)
        #expect(model.search.info == nil)
        #expect(Set(ids.values).isSubset(of: model.transactionIds))
    }

    @Test func splitLinesThatDoNotMatchAreStruckAndExpanded() {
        let (_, model, _) = searchModel()
        model.search.run("Memo: Essen")
        let subRows = model.rows.filter(\.isSubtransaction)
        #expect(subRows.map(\.id) == ["S1", "S2"])
        #expect(subRows.map(\.isExcludedFromSearch) == [false, true])
        #expect(model.summary.second.amountText == "-$30.00")
    }

    @Test func clearingTheSearchRestoresTheSplitExpansion() {
        let (_, model, _) = searchModel()
        model.search.run("Memo: Essen")
        model.search.clearClicked()
        #expect(!model.rows.contains { $0.isSubtransaction })
        #expect(model.search.text == "")
    }

    @Test func searchTotalCountsOnlyMatchingSplitLines() {
        let (_, model, _) = searchModel()
        model.search.run("Ausgang: >40")
        #expect(model.summary.second.title == "Suchsumme (3)")
        #expect(model.summary.second.amountText == "-$100.00")
        model.search.run("Ausgang: >10")
        #expect(model.summary.second.amountText == "-$150.00")
    }

    @Test func summaryBoxesRunTheirSearches() {
        var fixture = RegisterFixture()
        let uncleared = fixture.add(fixture.giro, -1)
        let (model, _) = fixture.spied()
        model.summaryClicked(.uncleared)
        #expect(model.search.filter?.label == "Ist: Vorgemerkt")
        #expect(model.transactionIds == [uncleared])
        model.summaryClicked(.cleared)
        #expect(model.search.filter?.label == "Ist: Gebucht oder abgeglichen")
        #expect(model.transactionIds == [fixture.startingBalanceId(of: fixture.giro)])
        model.summaryClicked(.working)
        #expect(model.search.filter?.label == "Ist: Gebucht oder abgeglichen")
    }

    @Test func cmdFRequestsSearchFocus() {
        let (model, _) = RegisterFixture().spied()
        let before = model.search.focusRequest
        model.search.focus()
        #expect(model.search.focusRequest == before + 1)
    }

    @Test func searchClearsTheSelection() {
        let (_, model, _) = searchModel()
        model.selectAll()
        model.search.run("rewe")
        #expect(model.selection.isEmpty)
    }

    @Test func searchesAndDateFiltersStayWithTheirAccount() {
        let (fixture, model, _) = searchModel()
        model.search.run("rewe")
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(model.search.filter == nil)
        model.navigation.selection = .account(fixture.giro)
        #expect(model.search.filter?.label == "rewe")
    }
}

@MainActor
@Suite struct RegisterDateFilterTests {
    private func model() -> (RegisterFixture, RegisterViewModel, String) {
        var fixture = RegisterFixture()
        let june = fixture.add(fixture.giro, -1, on: "2014-06-02")
        let (model, _) = fixture.spied()
        model.today = { day("2014-06-20") }
        return (fixture, model, june)
    }

    @Test func dateButtonTogglesTheTimeframeCallout() {
        let (_, model, _) = model()
        model.search.dateSelectorClicked()
        #expect(model.popup == .timeframe)
        #expect(model.search.timeframe?.start == day("2014-04-01"))
        #expect(model.search.timeframe?.end == day("2014-06-01"))
        model.search.dateSelectorClicked()
        #expect(model.popup == nil)
    }

    @Test func presetsApplyAtOnce() {
        let (_, model, june) = model()
        model.search.dateSelectorClicked()
        model.search.timeframePresetClicked(.thisMonth)
        #expect(model.popup == nil)
        #expect(model.search.dateSelectorTitle == "Dieser Monat")
        #expect(model.transactionIds == [june])
        #expect(model.search.info?.message == "1 Treffer im Zeitraum „Dieser Monat“")
        #expect(model.search.info?.clearButtonTitle == "Zeitraum zurücksetzen")
    }

    @Test func allDatesRemovesTheFilter() {
        let (_, model, _) = model()
        model.search.dateSelectorClicked()
        model.search.timeframePresetClicked(.thisMonth)
        model.search.dateSelectorClicked()
        model.search.timeframePresetClicked(.allDates)
        #expect(model.search.dateFilter == nil)
        #expect(model.search.dateSelectorTitle == "Alle Daten")
    }

    @Test func lastYearIsDisabledForAYoungAccount() {
        let (_, model, _) = model()
        model.search.dateSelectorClicked()
        #expect(!model.search.isTimeframePresetEnabled(.lastYear))
        model.search.timeframePresetClicked(.lastYear)
        #expect(model.search.dateFilter == nil)
    }

    @Test func customMonthsGetALabelOnDone() {
        let (_, model, _) = model()
        model.search.dateSelectorClicked()
        model.search.setTimeframeMonth(start: true, month: 5)
        model.search.setTimeframeMonth(start: false, month: 5)
        #expect(model.search.timeframeMonth(start: true) == 5)
        #expect(model.search.monthName(5) == "May")
        model.search.timeframeDone()
        #expect(model.search.dateSelectorTitle == "May 2014")
        #expect(model.transactionIds.count == 0)
    }

    @Test func monthChoicesAreClampedToTheRange() {
        let (_, model, _) = model()
        model.search.dateSelectorClicked()
        model.search.setTimeframeMonth(start: true, month: 1)
        #expect(model.search.timeframe?.start == day("2014-04-01"))
        #expect(model.search.timeframeYears == [2014])
    }

    @Test func yearChoicesMoveTheMonthToThatYear() {
        var fixture = RegisterFixture(start: day("2013-03-04"))
        fixture.add(fixture.giro, -1, on: "2014-06-02")
        let (model, _) = fixture.spied()
        model.today = { day("2014-06-20") }
        model.search.dateSelectorClicked()
        #expect(model.search.timeframeYears == [2013, 2014])
        model.search.setTimeframeYear(start: false, year: 2013)
        #expect(model.search.timeframe?.end == day("2013-06-01"))
        #expect(model.search.timeframeYear(start: false) == 2013)
        model.search.timeframeDone()
        #expect(model.search.dateSelectorTitle == "March 2013 bis June 2013")
    }

    @Test func closingThePopupDropsTheTimeframe() {
        let (_, model, _) = model()
        model.search.dateSelectorClicked()
        #expect(model.search.timeframe != nil)
        model.closePopup()
        #expect(model.popup == nil)
        #expect(model.search.timeframe == nil)
    }

    @Test func theSegmentedPresetsSelectAllDatesWithoutAFilterAndNothingForCustomMonths() {
        let (_, model, _) = model()
        #expect(model.search.timeframePreset == .allDates)
        model.search.dateSelectorClicked()
        model.search.timeframePresetClicked(.thisMonth)
        #expect(model.search.timeframePreset == .thisMonth)
        model.search.dateSelectorClicked()
        model.search.setTimeframeMonth(start: true, month: 5)
        model.search.setTimeframeMonth(start: false, month: 5)
        model.search.timeframeDone()
        #expect(model.search.timeframePreset == nil)
    }

    @Test func doneWithoutChangesKeepsThePreset() {
        let (_, model, _) = model()
        model.search.dateSelectorClicked()
        model.search.timeframePresetClicked(.thisMonth)
        model.search.dateSelectorClicked()
        model.search.timeframeDone()
        #expect(model.search.dateSelectorTitle == "Dieser Monat")
    }

    @Test func cancelKeepsTheFilter() {
        let (_, model, _) = model()
        model.search.dateSelectorClicked()
        model.search.setTimeframeMonth(start: true, month: 5)
        model.search.timeframeCancelled()
        #expect(model.search.dateFilter == nil)
        #expect(model.popup == nil)
    }

    @Test func reconciledSwitchOnlyWorksWithoutFilters() {
        var fixture = RegisterFixture()
        let reconciled = fixture.add(fixture.giro, -1, on: "2014-06-02", cleared: .reconciled)
        let (model, _) = fixture.spied()
        model.today = { day("2014-06-20") }
        model.setShowingReconciled(false)
        #expect(!model.transactionIds.contains(reconciled))
        model.search.dateSelectorClicked()
        model.search.timeframePresetClicked(.thisMonth)
        #expect(model.transactionIds == [reconciled])
        #expect(!model.isReconciledFilterEnabled)
    }
}

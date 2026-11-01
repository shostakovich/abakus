import AbakusCore
import Foundation
import Observation

@MainActor
@Observable
public final class RegisterSearchController {
    public static let allDatesTitle = DateFilterPreset.allDates.label
    static let clearSearchTitle = "Suche zurücksetzen"

    unowned let register: RegisterViewModel
    public internal(set) var focusRequest = 0
    public var isFocused = false

    init(register: RegisterViewModel) {
        self.register = register
    }

    public var text: String {
        get { register.viewState.searchText }
        set { register.viewState.searchText = newValue }
    }

    public var prompt: String {
        let name = register.accountName
        return name.isEmpty ? "Suchen" : name + " durchsuchen"
    }

    public var filter: RegisterSearchFilter? {
        get { register.viewState.searchFilter }
        set {
            register.viewState.searchFilter = newValue
            register.clearSelection()
            register.endEditsOvertakenByChanges()
        }
    }

    public var dateFilter: DateFilterSelection? {
        get { register.viewState.dateFilter }
        set {
            register.viewState.dateFilter = newValue
            register.clearSelection()
            register.endEditsOvertakenByChanges()
        }
    }

    private var expandedSplitsBeforeSearch: Set<String>? {
        get { register.viewState.expandedSplitsBeforeSearch }
        set { register.viewState.expandedSplitsBeforeSearch = newValue }
    }

    private var scrollBeforeSearch: RegisterScrollRequest.Target? {
        get { register.viewState.scrollBeforeSearch }
        set { register.viewState.scrollBeforeSearch = newValue }
    }

    public var isFiltered: Bool { filter != nil || dateFilter != nil }

    public private(set) var dropDown: SearchDropDownState? {
        get { register.overlayState.searchDropDown }
        set { register.overlayState.searchDropDown = newValue }
    }

    public private(set) var timeframe: TimeframeState? {
        get { register.overlayState.timeframe }
        set { register.overlayState.timeframe = newValue }
    }

    public var info: RegisterSearchInfo? {
        if let reconciliation = register.reconciliation.current {
            var message = "\(register.transactionIds.count) Buchungen"
            if let search = filter { message += " für „\(search.label)“" }
            message += " bis \(register.formatter.dateShort(reconciliation.statementDate)) (Datum des Banksaldos)"
            return RegisterSearchInfo(message: message, clearButtonTitle: filter == nil ? nil : Self.clearSearchTitle)
        }
        guard isFiltered else { return nil }
        var message = "\(register.transactionIds.count) Treffer"
        if let search = filter { message += " für „\(search.label)“" }
        if let date = dateFilter { message += " im Zeitraum „\(date.label)“" }
        let clearTitle = filter != nil ? Self.clearSearchTitle : "Zeitraum zurücksetzen"
        return RegisterSearchInfo(message: message, clearButtonTitle: clearTitle)
    }

    public func clearClicked() {
        guard !register.grid.clickedOutsideEditor() else { return }
        if filter != nil {
            text = ""
            clearFilter()
        } else {
            dateFilter = nil
        }
    }

    public var dateSelectorTitle: String { dateFilter?.label ?? Self.allDatesTitle }

    public func dateSelectorClicked() {
        guard !register.grid.clickedOutsideEditor() else { return }
        toggleTimeframe()
    }

    /// The box text without the trailing ", " the drop-down leaves behind.
    static func committedText(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        while trimmed.hasSuffix(",") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    var currentTerm: String {
        let text = self.text
        let start = text.lastIndex(of: ",").map { text.index(after: $0) } ?? text.startIndex
        return text[start...].trimmingCharacters(in: .whitespaces)
    }

    /// A comma commits like Enter, but the box keeps the focus for the next term.
    /// Emptying the box, also with its clear button, ends the search at once.
    public func boxChanged(_ text: String) {
        let typedComma = text.hasSuffix(",") && text.count > self.text.count
        self.text = text
        if typedComma || text.isEmpty && filter != nil {
            commit(focusingGrid: false)
            return
        }
        updateSuggestions()
    }

    func updateSuggestions() {
        let term = currentTerm
        let items = RegisterSearchSuggestions(
            budget: register.store.budget, isAllAccounts: register.isAllAccounts, today: register.today()
        )
        .suggestions(for: term)
        dropDown = items.isEmpty ? nil : SearchDropDownState(items: items, highlighted: nil)
    }

    public func moveHighlight(by offset: Int) {
        guard var dropDown, !dropDown.items.isEmpty else { return }
        let count = dropDown.items.count
        let current = dropDown.highlighted ?? (offset > 0 ? -1 : count)
        dropDown.highlighted = min(max(current + offset, 0), count - 1)
        self.dropDown = dropDown
    }

    public func submitted() {
        if let index = dropDown?.highlighted {
            pickSuggestion(at: index)
        } else {
            commit()
        }
    }

    /// Picking replaces the current term and runs the search; hint rows without search text do nothing.
    public func pickSuggestion(at index: Int) {
        guard let items = dropDown?.items, items.indices.contains(index) else { return }
        let pick = items[index].searchText
        guard !pick.isEmpty else { return }
        let text = self.text
        let head = text.lastIndex(of: ",").map { String(text[...$0]) + " " } ?? ""
        self.text = head + pick + ", "
        commit(focusingGrid: false)
    }

    /// Drop-down, then box text, then the search; false once the box gives up focus.
    @discardableResult
    public func escapePressed() -> Bool {
        if dropDown != nil {
            dropDown = nil
        } else if !text.isEmpty {
            text = ""
            commit(focusingGrid: false)
        } else {
            cancel()
            return false
        }
        return true
    }

    public func focusChanged(_ focused: Bool) {
        isFocused = focused
        if !focused {
            dropDown = nil
            if Self.committedText(text).isEmpty {
                text = ""
                commit()
            }
        }
    }

    public func focus() {
        guard register.acceptsRegisterKeys else { return }
        focusRequest += 1
    }

    /// Nothing happens when the box text did not change.
    public func commit(focusingGrid: Bool = true) {
        dropDown = nil
        let text = Self.committedText(self.text)
        guard text != (filter?.label ?? "") else { return }
        if text.isEmpty {
            clearFilter()
        } else {
            if filter == nil {
                expandedSplitsBeforeSearch = register.expandedSplits
                scrollBeforeSearch = register.savedScrollOffset().map { .offset($0) } ?? .top
            }
            let query = RegisterSearchQuery(text, decimalSeparator: register.formatter.currencyLocale.decimalSeparator)
            filter = RegisterSearchFilter(label: text, query: query)
            for (id, match) in register.derived.searchMatches where match.expandsSplit {
                register.expandedSplits.insert(id)
            }
            register.requestScroll(register.sortOrder.ascending ? .bottom : .top)
        }
        refreshDateFilterPreset()
        if focusingGrid { register.gridFocusRequest += 1 }
    }

    /// Notifier clicks and the payee dialog put the search into the box with a trailing separator (`is:Error, `).
    public func run(_ text: String) {
        self.text = text + ", "
        commit()
    }

    /// The scroll position and split expansion from before the search come back.
    func clearFilter() {
        guard filter != nil else { return }
        filter = nil
        if let splits = expandedSplitsBeforeSearch { register.expandedSplits = splits }
        expandedSplitsBeforeSearch = nil
        register.requestScroll(scrollBeforeSearch ?? .top)
        scrollBeforeSearch = nil
    }

    public func cancel() {
        dropDown = nil
        text = ""
        clearFilter()
        dateFilter = nil
    }

    private func refreshDateFilterPreset() {
        guard let selection = dateFilter, selection.preset != nil else { return }
        let resolved = selection.resolved(today: register.today(), range: dateFilterRange)
        if resolved != selection { dateFilter = resolved }
    }

    public var dateFilterRange: DateFilterRange {
        register.store.budget.dateFilterRange(forAccount: register.accountKey ?? "", today: register.today())
    }

    func toggleTimeframe() {
        if register.popup == .timeframe {
            register.closePopup()
            return
        }
        let range = dateFilterRange
        let selection = dateFilter
        timeframe = TimeframeState(
            start: range.clamped(selection?.start ?? range.start), end: range.clamped(selection?.end ?? range.end),
            range: range)
        register.menuRequest = nil
        register.popup = .timeframe
    }

    public func isTimeframePresetEnabled(_ preset: DateFilterPreset) -> Bool {
        (timeframe?.range ?? dateFilterRange).isEnabled(preset, today: register.today())
    }

    /// All Dates stands for no filter; a custom range selects no preset.
    public var timeframePreset: DateFilterPreset? {
        dateFilter == nil ? .allDates : dateFilter?.preset
    }

    public func timeframePresetClicked(_ preset: DateFilterPreset) {
        guard isTimeframePresetEnabled(preset) else { return }
        let selection = DateFilterSelection.preset(preset, today: register.today(), range: dateFilterRange)
        register.closePopup()
        setDateSelection(selection)
    }

    /// Done without touching the months keeps the current filter.
    public func timeframeDone() {
        guard let state = timeframe else { return }
        register.closePopup()
        guard state.isChanged else { return }
        setDateSelection(DateFilterSelection.custom(state.start, state.end, formatter: register.formatter))
    }

    public func timeframeCancelled() {
        register.closePopup()
    }

    func setDateSelection(_ selection: DateFilterSelection?) {
        dateFilter = selection
        register.requestScroll(register.sortOrder.ascending ? .bottom : .top)
    }

    public func timeframeMonth(start: Bool) -> Int? {
        timeframe.map { (start ? $0.start : $0.end).month }
    }

    public func timeframeYear(start: Bool) -> Int? {
        timeframe.map { (start ? $0.start : $0.end).year }
    }

    public var timeframeYears: [Int] { timeframe?.range.years ?? [] }

    public func monthName(_ month: Int) -> String {
        register.formatter.monthName(month)
    }

    public func setTimeframeMonth(start: Bool, month: Int) {
        guard var state = timeframe else { return }
        let date = start ? state.start : state.end
        updateTimeframe(&state, start: start, DateWithoutTime(year: date.year, month: month, day: 1))
    }

    public func setTimeframeYear(start: Bool, year: Int) {
        guard var state = timeframe else { return }
        let date = start ? state.start : state.end
        updateTimeframe(&state, start: start, DateWithoutTime(year: year, month: date.month, day: 1))
    }

    private func updateTimeframe(_ state: inout TimeframeState, start: Bool, _ date: DateWithoutTime) {
        state.isChanged = true
        if start {
            state.start = state.range.clamped(date)
        } else {
            state.end = state.range.clamped(date)
        }
        timeframe = state
    }
}

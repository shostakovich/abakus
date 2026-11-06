import AbakusCore
import Foundation
import Observation

@MainActor
@Observable
public final class RegisterSearchController {
    static let clearSearchTitle = "Suche zurücksetzen"

    unowned let register: RegisterViewModel
    public internal(set) var focusRequest = 0
    public var isFocused = false

    init(register: RegisterViewModel) {
        self.register = register
    }

    public private(set) var text: String {
        get { register.viewState.searchText }
        set { register.viewState.searchText = newValue }
    }

    public var prompt: String {
        let name = register.accountName
        return name.isEmpty ? "Suchen" : name + " durchsuchen"
    }

    var search: RegisterSearch { RegisterSearch(text) }

    public var isSearching: Bool { !search.isEmpty }

    private var expandedSplitsBeforeSearch: Set<String>? {
        get { register.viewState.expandedSplitsBeforeSearch }
        set { register.viewState.expandedSplitsBeforeSearch = newValue }
    }

    private var scrollBeforeSearch: RegisterScrollRequest.Target? {
        get { register.viewState.scrollBeforeSearch }
        set { register.viewState.scrollBeforeSearch = newValue }
    }

    public var info: RegisterSearchInfo? {
        if let reconciliation = register.reconciliation.current {
            var message = "\(register.transactionIds.count) Buchungen"
            if isSearching { message += " für „\(text.trimmingCharacters(in: .whitespaces))“" }
            message += " bis \(register.headerDate(reconciliation.statementDate)) (Datum des Banksaldos)"
            return RegisterSearchInfo(message: message, clearButtonTitle: isSearching ? Self.clearSearchTitle : nil)
        }
        guard isSearching else { return nil }
        let message = "\(register.transactionIds.count) Treffer für „\(text.trimmingCharacters(in: .whitespaces))“"
        return RegisterSearchInfo(message: message, clearButtonTitle: Self.clearSearchTitle)
    }

    public func clearClicked() {
        guard !register.grid.clickedOutsideEditor() else { return }
        cancel()
    }

    /// Every change filters at once; the first one keeps the splits and the scroll position for the end.
    public func boxChanged(_ text: String) {
        guard text != self.text else { return }
        let wasSearching = isSearching
        if !wasSearching && !RegisterSearch(text).isEmpty {
            expandedSplitsBeforeSearch = register.expandedSplits
            scrollBeforeSearch = register.savedScrollOffset().map { .offset($0) } ?? .top
        }
        let before = search
        self.text = text
        guard search != before else { return }
        register.clearSelection()
        register.endEditsOvertakenByChanges()
        guard isSearching else {
            restoreAfterSearch()
            return
        }
        for (id, hit) in register.derived.searchHits where hit == .part {
            register.expandedSplits.insert(id)
        }
        register.requestScroll(register.sortOrder.ascending ? .bottom : .top)
    }

    public func submitted() {
        register.gridFocusRequest += 1
    }

    /// Box text first, then the focus; false once the box gives up focus.
    @discardableResult
    public func escapePressed() -> Bool {
        guard text.isEmpty else {
            boxChanged("")
            return true
        }
        return false
    }

    public func focusChanged(_ focused: Bool) {
        isFocused = focused
    }

    public func focus() {
        guard register.acceptsRegisterKeys else { return }
        focusRequest += 1
    }

    public func run(_ text: String) {
        boxChanged(text)
    }

    public func cancel() {
        boxChanged("")
    }

    private func restoreAfterSearch() {
        if let splits = expandedSplitsBeforeSearch { register.expandedSplits = splits }
        expandedSplitsBeforeSearch = nil
        register.requestScroll(scrollBeforeSearch ?? .top)
        scrollBeforeSearch = nil
    }
}

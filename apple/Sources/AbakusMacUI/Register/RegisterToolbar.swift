import AbakusCore
import AbakusUI
import SwiftUI

/// The row under the window toolbar: Buchung, the open notices, Ansicht and the search.
struct RegisterToolbar: View {
    static let addTitle = "Buchung"

    let model: RegisterViewModel

    var body: some View {
        HStack(spacing: 8) {
            addButton
            RegisterNotifierChips(notifiers: model.notifiers).layoutPriority(1)
            Spacer(minLength: 8)
            viewButton
            searchField
        }
        .controlSize(.regular)
        .padding(.horizontal, RegisterHeaderMetrics.horizontalPadding)
        .padding(.vertical, 8)
    }

    private var addButton: some View {
        Button(action: model.addTransactionClicked) {
            Label(Self.addTitle, systemImage: "plus")
        }
        .fixedSize()
        .disabled(!model.canAddTransactions)
        .help(RegisterViewModel.addTitle)
    }

    private var viewButton: some View {
        Menu(model.viewMenuTitle) {
            RegisterMenuItemsView(items: model.viewMenu, perform: model.viewMenuChosen)
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private var searchField: some View {
        let search = model.search
        return RegisterSearchField(
            search: search, text: search.text, prompt: search.prompt, focusRequest: search.focusRequest
        )
        // A fixed width: resizing the field while it edits leaves the field editor scrolled.
        .frame(width: RegisterMetrics.searchFieldWidth)
    }
}

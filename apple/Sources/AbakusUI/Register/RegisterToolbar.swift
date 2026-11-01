import AbakusCore
import SwiftUI

/// The header's second row: Buchung (with Umbuchung beside it), the open notices, Ansicht and the search.
struct RegisterToolbar: View {
    static let addTitle = "Buchung"
    static let viewTitle = "Ansicht"

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
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var addButton: some View {
        Group {
            if model.showsTransferButton {
                Menu {
                    Button(RegisterViewModel.transferTitle, action: model.makeTransferClicked)
                } label: {
                    Label(Self.addTitle, systemImage: "plus")
                } primaryAction: {
                    model.addTransactionClicked()
                }
            } else {
                Button(action: model.addTransactionClicked) {
                    Label(Self.addTitle, systemImage: "plus")
                }
            }
        }
        .fixedSize()
        .disabled(!model.canAddTransactions)
        .help(RegisterViewModel.addTitle)
    }

    private var viewButton: some View {
        Menu(Self.viewTitle) {
            RegisterMenuItemsView(items: model.viewMenu, perform: model.viewMenuChosen)
        }
        .menuStyle(.button)
        .fixedSize()
        .registerAnchor(.viewMenu)
    }

    private var searchField: some View {
        let search = model.search
        return RegisterSearchField(
            search: search, text: search.text, prompt: search.prompt, dropDown: search.dropDown,
            focusRequest: search.focusRequest
        )
        // A fixed width: resizing the field while it edits leaves the field editor scrolled.
        .frame(width: RegisterMetrics.searchFieldWidth)
    }
}

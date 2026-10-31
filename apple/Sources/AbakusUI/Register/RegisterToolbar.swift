import AbakusCore
import SwiftUI

/// The register's window toolbar: the selection's actions; the filters and search; the + menu.
struct RegisterToolbar: ToolbarContent {
    static let reconciledTitle = "Abgeglichene Buchungen zeigen"
    static let reconciledDisabledTip = "Beim Suchen erscheinen abgeglichene und nicht abgeglichene Buchungen."
    static let addMenuTitle = "Hinzufügen"

    let model: RegisterViewModel
    let anchors: ToolbarAnchors

    var body: some ToolbarContent {
        let isReconciling = model.isReconciling
        ToolbarItem(placement: .navigation) {
            editTransactionsButton
        }
        ToolbarSpacer(.flexible)
        ToolbarItemGroup(placement: .automatic) {
            if !isReconciling {
                dateButton
                reconciledToggle
            }
            searchField
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .automatic) {
            addMenu
        }
    }

    private var editTransactionsButton: some View {
        Button(action: model.editTransactionsClicked) {
            pullDownLabel(model.actionButtonTitle.trimmingCharacters(in: .whitespaces))
        }
        .disabled(!model.isActionButtonEnabled)
        .toolbarAnchor(.actionButton, in: anchors)
    }

    private var dateButton: some View {
        Button(action: model.search.dateSelectorClicked) {
            pullDownLabel(model.search.dateSelectorTitle)
        }
        .toolbarAnchor(.dateButton, in: anchors)
    }

    private func pullDownLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: title)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var reconciledToggle: some View {
        let isEnabled = model.isReconciledFilterEnabled
        let isShowing = Binding(get: { model.isShowingReconciled }, set: { model.setShowingReconciled($0) })
        return Toggle(isOn: isShowing) {
            Label(Self.reconciledTitle, systemImage: "lock")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .disabled(!isEnabled)
        .help(isEnabled ? Self.reconciledTitle : Self.reconciledDisabledTip)
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

    private var addMenu: some View {
        Menu {
            Button(RegisterViewModel.addTitle, action: model.addTransactionClicked)
            if model.showsTransferButton {
                Button(RegisterViewModel.transferTitle, action: model.makeTransferClicked)
            }
        } label: {
            Label(Self.addMenuTitle, systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .disabled(!model.canAddTransactions)
    }
}

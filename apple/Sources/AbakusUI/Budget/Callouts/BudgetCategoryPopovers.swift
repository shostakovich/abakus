import AbakusCore
import SwiftUI

struct BudgetCategoryPopover: View {
    static let width: CGFloat = 380

    let controller: BudgetCalloutController
    let form: BudgetCategoryForm
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let deletion = form.deletion {
                BudgetCategoryDeletionView(controller: controller, form: form, deletion: deletion)
            } else {
                editing
            }
        }
        .font(ThemeFont.body.font)
        .foregroundStyle(ThemeColor.text)
        .frame(width: Self.width, alignment: .leading)
        .onAppear { isFocused = true }
        .onChange(of: form.focusRequest) { isFocused = true }
    }

    @ViewBuilder
    private var editing: some View {
        @Bindable var controller = controller
        PopoverTitle(form.title)
        TextField("Name", text: $controller.categoryName)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit(controller.categoryDone)
        if !form.isNew && form.canDelete {
            Button(role: .destructive, action: controller.deleteCategoryClicked) {
                Label(form.deleteTitle, systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ThemeColor.negative)
            .fixedSize()
        }
        if form.hasTarget {
            Divider()
            BudgetTargetSection(controller: controller, form: form)
        }
        Divider()
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Abbrechen", action: controller.categoryCancelled)
            Button("Fertig", action: controller.categoryDone).buttonStyle(.borderedProminent)
        }
    }
}

private struct BudgetCategoryDeletionView: View {
    static let noSuccessor = "Es gibt keine andere Kategorie, die alles übernehmen kann."
    static let successorLabel = "Buchungen, Zuweisungen und Geld gehen in"
    static let reconciledWarning = "Auch abgeglichene Buchungen bekommen die neue Kategorie."

    let controller: BudgetCalloutController
    let form: BudgetCategoryForm
    let deletion: BudgetCategoryDeletion

    var body: some View {
        @Bindable var controller = controller
        PopoverTitle(form.deletionTitle)
        if deletion.successors.isEmpty {
            Text(verbatim: Self.noSuccessor)
                .foregroundStyle(ThemeColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: Self.successorLabel)
                BudgetCategoryChoicePicker(
                    label: Self.successorLabel, groups: deletion.successors,
                    selection: $controller.deletionSuccessorId, leading: ("Kategorie wählen", nil))
            }
            if deletion.changesReconciledTransactions {
                Label {
                    Text(verbatim: Self.reconciledWarning).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: StatusSymbol.warning).foregroundStyle(ThemeColor.warning)
                }
            }
        }
        Divider()
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Abbrechen", action: controller.deletionCancelled)
            if !deletion.successors.isEmpty {
                Button("Löschen", role: .destructive, action: controller.confirmDeletionClicked)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(deletion.successorId == nil)
            }
        }
    }
}

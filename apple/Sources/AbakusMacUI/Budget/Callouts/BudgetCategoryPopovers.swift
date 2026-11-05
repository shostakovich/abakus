import AbakusCore
import AbakusUI
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
        .onAppear { if form.isNew { isFocused = true } }
        .onChange(of: form.focusRequest) { isFocused = true }
    }

    @ViewBuilder
    private var editing: some View {
        @Bindable var controller = controller
        BudgetCategoryTitleField(name: $controller.categoryName, prompt: form.title, isFocused: $isFocused)
            .onSubmit(controller.categoryDone)
        if form.hasTarget {
            Divider()
            BudgetTargetSection(controller: controller, form: form)
        }
        Divider()
        HStack(spacing: 8) {
            if !form.isNew && form.canDelete {
                Button(role: .destructive, action: controller.deleteCategoryClicked) {
                    Label(form.deleteTitle, systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(ThemeColor.negative)
                .fixedSize()
            }
            Spacer(minLength: 0)
            Button("Abbrechen", action: controller.categoryCancelled)
            Button("Fertig", action: controller.categoryDone).buttonStyle(.borderedProminent)
        }
    }
}

/// The popover's title is the name itself, emoji included: a click renames, as in Reminders' list info.
private struct BudgetCategoryTitleField: View {
    @Binding var name: String
    let prompt: String
    var isFocused: FocusState<Bool>.Binding
    @State private var isHovered = false

    var body: some View {
        let isActive = isFocused.wrappedValue || isHovered
        TextField("Name", text: $name, prompt: Text(verbatim: prompt))
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .focused(isFocused)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isActive ? AnyShapeStyle(FillShapeStyle().tertiary) : AnyShapeStyle(ThemeColor.groupFill),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(.isHeader)
    }
}

private struct BudgetCategoryDeletionView: View {
    let controller: BudgetCalloutController
    let form: BudgetCategoryForm
    let deletion: BudgetCategoryDeletion

    var body: some View {
        @Bindable var controller = controller
        PopoverTitle(form.deletionTitle)
        if deletion.successors.isEmpty {
            Text(verbatim: BudgetCategoryDeletion.noSuccessor)
                .foregroundStyle(ThemeColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: BudgetCategoryDeletion.successorLabel)
                BudgetCategoryChoicePicker(
                    label: BudgetCategoryDeletion.successorLabel, groups: deletion.successors,
                    selection: $controller.deletionSuccessorId, leading: ("Kategorie wählen", nil))
            }
            if deletion.changesReconciledTransactions {
                Label {
                    Text(verbatim: BudgetCategoryDeletion.reconciledWarning)
                        .fixedSize(horizontal: false, vertical: true)
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

import AbakusCore
import SwiftUI

struct BudgetAssignPopover: View {
    let controller: BudgetCalloutController
    let form: BudgetAssignForm
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                PopoverTitle("In eine Kategorie verteilen")
                Text(verbatim: form.monthTitle).foregroundStyle(ThemeColor.secondaryText)
            }
            VStack(alignment: .leading, spacing: 8) {
                BudgetCategoryChoicePicker(
                    label: "Kategorie", groups: form.categories, selection: $controller.assignCategoryId)
                HStack(spacing: 6) {
                    Text("Betrag")
                    Spacer(minLength: 0)
                    BudgetAmountField(
                        label: "Betrag", text: $controller.assignAmount, locale: controller.formatter.currencyLocale,
                        isFocused: $isAmountFocused)
                }
                Text(verbatim: form.freeText).foregroundStyle(ThemeColor.secondaryText)
            }
            if let error = form.error {
                Text(verbatim: error)
                    .foregroundStyle(ThemeColor.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Abbrechen", action: controller.assignCancelled)
                Button("Zuweisen", action: controller.assignClicked)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(ThemeFont.body.font)
        .foregroundStyle(ThemeColor.text)
        .frame(width: BudgetAvailablePopover.width, alignment: .leading)
        .onAppear { isAmountFocused = true }
    }
}

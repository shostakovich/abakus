import AbakusCore
import SwiftUI

struct BudgetAvailablePopover: View {
    static let width: CGFloat = 340

    let controller: BudgetCalloutController
    let form: BudgetAvailableForm
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 12) {
            header
            if form.isOverspent {
                Picker("Aktion", selection: $controller.availableMode) {
                    ForEach(BudgetAvailableMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            switch form.mode {
            case .cover: cover
            case .move: move
            }
            if let error = form.error {
                Text(verbatim: error)
                    .foregroundStyle(ThemeColor.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .font(ThemeFont.body.font)
        .foregroundStyle(ThemeColor.text)
        .frame(width: Self.width, alignment: .leading)
        .onAppear { isAmountFocused = form.mode == .move }
        .onChange(of: form.mode) { isAmountFocused = form.mode == .move }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            PopoverTitle(form.categoryName)
            HStack(spacing: 8) {
                Text(verbatim: form.monthTitle).foregroundStyle(ThemeColor.secondaryText)
                Spacer(minLength: 0)
                Text(verbatim: controller.formatter.currency(form.available))
                    .monospacedDigit()
                    .fontWeight(.medium)
                    .foregroundStyle(form.isOverspent ? ThemeColor.negative : ThemeColor.text)
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        @Bindable var controller = controller
        if form.sources.isEmpty {
            Text(verbatim: BudgetCalloutController.noSources)
                .foregroundStyle(ThemeColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: controller.coverLabel)
                Picker(controller.coverLabel, selection: $controller.coverSourceId) {
                    ForEach(form.sources, id: \.categoryId) { source in
                        Text(verbatim: controller.coverSourceLabel(source)).tag(source.categoryId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(verbatim: controller.remainingLabel).foregroundStyle(ThemeColor.secondaryText)
                    Spacer(minLength: 0)
                    Text(verbatim: controller.remainingText).monospacedDigit()
                }
            }
        }
    }

    private var move: some View {
        @Bindable var controller = controller
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Betrag")
                Spacer(minLength: 0)
                BudgetAmountField(
                    label: "Betrag", text: $controller.moveAmount, locale: controller.formatter.currencyLocale,
                    isFocused: $isAmountFocused)
            }
            Picker("Richtung", selection: $controller.moveDirection) {
                ForEach(BudgetMoveDirection.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            BudgetCategoryChoicePicker(
                label: "Andere Kategorie", groups: form.others, selection: $controller.moveOtherId,
                leading: (DefaultCategories.readyToAssignName, controller.readyToAssignCategoryId))
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: controller.editCategoryClicked) {
                HStack(spacing: 2) {
                    Text("Kategorie bearbeiten")
                    Image(systemName: "chevron.right").imageScale(.small)
                }
            }
            .buttonStyle(.link)
            .fixedSize()
            Spacer(minLength: 0)
            Button("Abbrechen", action: controller.availableCancelled)
            switch form.mode {
            case .cover:
                Button(BudgetAvailableMode.cover.title, action: controller.coverClicked)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.sources.isEmpty)
            case .move:
                Button(BudgetAvailableMode.move.title, action: controller.moveClicked)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

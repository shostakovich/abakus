#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    enum BudgetSheetField: Hashable {
        case assigned, name, target
    }

    struct BudgetSheet: View {
        let model: BudgetViewModel
        var isPopover = false
        @FocusState private var focus: BudgetSheetField?

        var body: some View {
            let callouts = model.callouts
            NavigationStack {
                Group {
                    if let form = callouts.category, let deletion = form.deletion {
                        BudgetDeletionSheet(controller: callouts, form: form, deletion: deletion)
                    } else if let form = callouts.category, let available = callouts.availableForm {
                        BudgetCategorySheet(
                            model: model, form: form, available: available, showsClose: !isPopover, focus: $focus)
                    } else if let form = callouts.category {
                        BudgetGroupSheet(model: model, form: form, focus: $focus)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .scrollContentBackground(.hidden)
                .background(ThemeColor.groupedBackground)
                .scrollEdgeEffectStyle(.hard, for: .top)
                .toolbarBackground(ThemeColor.groupedBackground, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Fertig") { focus = nil }
                    }
                }
                .safeAreaInset(edge: .bottom) { banner }
                .animation(.smooth(duration: 0.25), value: model.undoNotice?.id)
            }
            .presentationBackground(ThemeColor.groupedBackground)
        }

        @ViewBuilder
        private var banner: some View {
            if let notice = model.undoNotice {
                BudgetUndoBanner(model: model, notice: notice)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Every action applies at once, so the sheet only closes and the popover has no Close button.
    private struct BudgetCategorySheet: View {
        let model: BudgetViewModel
        let form: BudgetCategoryForm
        let available: BudgetAvailableForm
        let showsClose: Bool
        var focus: FocusState<BudgetSheetField?>.Binding

        var body: some View {
            @Bindable var controller = model.callouts
            let cell = BudgetCellID(month: available.month, categoryId: available.categoryId)
            Form {
                Group {
                    if let breakdown = model.availableBreakdown(of: available.categoryId, in: available.month) {
                        BudgetAvailableSection(
                            model: model, breakdown: breakdown, available: available, cell: cell, focus: focus)
                    }
                    BudgetTargetSection(controller: controller, form: form, focus: focus)
                    Section {
                        Button(form.deleteTitle, systemImage: "trash", role: .destructive) {
                            focus.wrappedValue = nil
                            controller.deleteCategoryClicked()
                        }
                        .foregroundStyle(ThemeColor.negative)
                    }
                }
                // The popover would lay its rows on a grey fill; the sheet's rows keep theirs in both.
                .listRowBackground(ThemeColor.groupedRowBackground)
            }
            .environment(\.defaultMinListRowHeight, 40)
            .listSectionSpacing(.compact)
            .scrollIndicatorsFlash(onAppear: true)
            .modifier(ReportsFormHeight())
            .navigationTitle(form.name)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BudgetSheetTitleField(
                        name: $controller.categoryName, prompt: form.title, subtitle: available.monthTitle,
                        focus: focus, onSubmit: controller.categoryNameSubmitted)
                }
                .sharedBackgroundVisibility(.hidden)
                if showsClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen", systemImage: "xmark", role: .close) {
                            focus.wrappedValue = nil
                            model.touchSheetDismissed()
                        }
                    }
                }
            }
            .onChange(of: form.focusRequest) { focus.wrappedValue = .name }
        }
    }

    private struct BudgetAvailableSection: View {
        let model: BudgetViewModel
        let breakdown: BudgetAvailableBreakdown
        let available: BudgetAvailableForm
        let cell: BudgetCellID
        var focus: FocusState<BudgetSheetField?>.Binding
        @State private var assigned = ""

        var body: some View {
            let stored = model.assignedText(cell)
            Section {
                LabeledContent(BudgetAvailableBreakdown.carriedLabel) { amount(breakdown.carried) }
                LabeledContent(breakdown.assignedLabel) {
                    TextField(breakdown.assignedLabel, text: typed, prompt: Text(verbatim: model.zeroText))
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .amountKeyboard()
                        .submitLabel(.done)
                        .focused(focus, equals: .assigned)
                        .onSubmit(commit)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(ThemeColor.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: 160)
                }
                .onChange(of: stored, initial: true) { assigned = stored }
                .onChange(of: focus.wrappedValue) { old, _ in if old == .assigned { commit() } }
                .onChange(of: model.sheetAssignedRefusals) { focus.wrappedValue = .assigned }
                .onDisappear(perform: commit)
                if let error = model.sheetAssignedError {
                    Text(verbatim: error)
                        .font(.footnote)
                        .foregroundStyle(ThemeColor.negative)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowSeparator(.hidden, edges: .top)
                }
                LabeledContent(breakdown.activityLabel) { amount(breakdown.activity) }
                LabeledContent {
                    Text(verbatim: breakdown.available)
                        .monospacedDigit()
                        .fontWeight(.bold)
                        .foregroundStyle(availableColor)
                } label: {
                    Text("Verfügbar").fontWeight(.semibold)
                }
            } header: {
                Text("Verfügbar")
            }
        }

        private var availableColor: Color {
            if breakdown.isOverspent { return ThemeColor.negative }
            switch breakdown.marker {
            case .underfunded: return ThemeColor.warning
            case .funded: return ThemeColor.positive
            case .snoozed, nil: return ThemeColor.text
            }
        }

        private func amount(_ text: String) -> some View {
            Text(verbatim: text).monospacedDigit().foregroundStyle(ThemeColor.text)
        }

        private var typed: Binding<String> {
            Binding {
                assigned
            } set: { text in
                assigned = text
                model.sheetAssignedChanged(text, in: cell)
            }
        }

        private func commit() {
            model.commitSheetAssigned()
        }
    }

    private struct BudgetGroupSheet: View {
        let model: BudgetViewModel
        let form: BudgetCategoryForm
        var focus: FocusState<BudgetSheetField?>.Binding

        var body: some View {
            @Bindable var controller = model.callouts
            Form {
                if form.isMaster && !form.isNew {
                    Section {
                        Button("Neue Kategorie", systemImage: "plus") {
                            model.addSubCategoryClicked(masterId: form.categoryId)
                        }
                    }
                }
                if !form.isNew && form.canDelete {
                    Section {
                        Button(form.deleteTitle, systemImage: "trash", role: .destructive) {
                            controller.deleteCategoryClicked()
                        }
                        .foregroundStyle(ThemeColor.negative)
                    }
                }
            }
            .navigationTitle(form.isNew ? form.title : form.name)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BudgetSheetTitleField(
                        name: $controller.categoryName, prompt: form.title, subtitle: nil, focus: focus,
                        onSubmit: form.isNew ? controller.categoryDone : controller.categoryNameSubmitted)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .cancellationAction) {
                    Button(form.isNew ? "Abbrechen" : "Schließen", systemImage: "xmark", role: .close) {
                        focus.wrappedValue = nil
                        model.touchSheetDismissed()
                    }
                }
                if form.isNew {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hinzufügen", systemImage: "checkmark", role: .confirm, action: controller.categoryDone)
                    }
                }
            }
            .onAppear { if form.isNew { focus.wrappedValue = .name } }
            .onChange(of: form.focusRequest) { focus.wrappedValue = .name }
        }
    }

    private struct BudgetDeletionSheet: View {
        let controller: BudgetCalloutController
        let form: BudgetCategoryForm
        let deletion: BudgetCategoryDeletion

        var body: some View {
            @Bindable var controller = controller
            Form {
                if deletion.successors.isEmpty {
                    Text(verbatim: BudgetCategoryDeletion.noSuccessor).foregroundStyle(ThemeColor.secondaryText)
                } else {
                    Section {
                        BudgetCategoryPicker(
                            label: BudgetCategoryDeletion.successorLabel, groups: deletion.successors,
                            selection: $controller.deletionSuccessorId, leading: ("Kategorie wählen", nil))
                    } header: {
                        Text(verbatim: BudgetCategoryDeletion.successorLabel)
                    } footer: {
                        if deletion.changesReconciledTransactions {
                            Label(BudgetCategoryDeletion.reconciledWarning, systemImage: StatusSymbol.warning)
                        }
                    }
                }
            }
            .modifier(ReportsFormHeight())
            .navigationTitle(form.deletionTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: controller.deletionCancelled)
                }
                if !deletion.successors.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Löschen", role: .destructive, action: controller.confirmDeletionClicked)
                            .disabled(deletion.successorId == nil)
                    }
                }
            }
        }
    }

    /// The sheet's title is the name itself, emoji included: a tap renames, as in Reminders' list info.
    private struct BudgetSheetTitleField: View {
        @Binding var name: String
        let prompt: String
        let subtitle: String?
        var focus: FocusState<BudgetSheetField?>.Binding
        let onSubmit: () -> Void

        var body: some View {
            let isEditing = focus.wrappedValue == .name
            VStack(spacing: 1) {
                TextField("Name", text: $name, prompt: Text(verbatim: prompt))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .focused(focus, equals: .name)
                    .onSubmit(onSubmit)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .background(
                        isEditing ? AnyShapeStyle(ThemeColor.fieldBackground) : AnyShapeStyle(ThemeColor.groupFill),
                        in: Capsule()
                    )
                    .contentShape(.hoverEffect, Capsule())
                    .hoverEffect(.highlight)
                    .accessibilityLabel("Name")
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(ThemeColor.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 260)
        }
    }

    struct BudgetCategoryPicker<Selection: Hashable>: View {
        let label: String
        let groups: [BudgetCategoryChoiceGroup]
        @Binding var selection: Selection
        var leading: (title: String, tag: Selection)?

        var body: some View {
            Picker(label, selection: $selection) {
                if let leading {
                    Text(verbatim: leading.title).tag(leading.tag)
                }
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.categories) { Text(verbatim: $0.name).tag($0.id) }
                    }
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    struct BudgetAmountField: View {
        let label: String
        @Binding var text: String
        var focus: FocusState<BudgetSheetField?>.Binding
        let field: BudgetSheetField

        var body: some View {
            LabeledContent(label) {
                TextField(label, text: $text)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .amountKeyboard(.decimalPad)
                    .focused(focus, equals: field)
            }
        }
    }
#endif

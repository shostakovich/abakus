#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    enum BudgetSheetField: Hashable {
        case assigned, move, assign, name, target
    }

    struct BudgetSheet: View {
        let model: BudgetViewModel
        var isPopover = false
        @FocusState private var focus: BudgetSheetField?

        var body: some View {
            let callouts = model.callouts
            NavigationStack {
                Group {
                    if let form = callouts.assignForm {
                        BudgetAssignSheet(controller: callouts, form: form, focus: $focus)
                    } else if let form = callouts.category, let deletion = form.deletion {
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
            }
            .presentationBackground(ThemeColor.groupedBackground)
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
                        NavigationLink {
                            BudgetMoveView(controller: controller, focus: focus)
                        } label: {
                            Label("Geld verschieben", systemImage: "arrow.left.arrow.right")
                        }
                    }
                    Section("Name") {
                        TextField("Name", text: $controller.categoryName)
                            .focused(focus, equals: .name)
                            .submitLabel(.done)
                    }
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
            .navigationTitle(available.categoryName)
            .navigationSubtitle(available.monthTitle)
            .toolbar {
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
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent(breakdown.assignedLabel) {
                        TextField(breakdown.assignedLabel, text: typed, prompt: Text(verbatim: model.zeroText))
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .keyboardType(.numbersAndPunctuation)
                            .submitLabel(.done)
                            .focused(focus, equals: .assigned)
                            .onSubmit(commit)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(ThemeColor.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: 160)
                    }
                    BudgetQuickAmounts(model: model, cell: cell) { focus.wrappedValue = nil }
                }
                .onChange(of: stored, initial: true) { assigned = stored }
                .onChange(of: focus.wrappedValue) { old, _ in if old == .assigned { commit() } }
                .onDisappear(perform: commit)
                LabeledContent(breakdown.activityLabel) { amount(breakdown.activity) }
                LabeledContent {
                    Text(verbatim: breakdown.available)
                        .monospacedDigit()
                        .fontWeight(.bold)
                        .foregroundStyle(availableColor)
                } label: {
                    Text("Verfügbar").fontWeight(.semibold)
                }
                if available.isOverspent {
                    BudgetCoverRows(controller: model.callouts, form: available)
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

    private struct BudgetQuickAmounts: View {
        let model: BudgetViewModel
        let cell: BudgetCellID
        let onChosen: () -> Void

        var body: some View {
            ChipFlow(spacing: 8) {
                ForEach(model.quickBudgetOptions(for: cell), id: \.fill) { option in
                    Button {
                        onChosen()
                        model.quickBudgetOptionChosen(option, for: cell)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: Self.title(option.fill))
                                .font(.caption2)
                                .foregroundStyle(ThemeColor.secondaryText)
                            Text(verbatim: model.formatter.currency(option.amount))
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(ThemeColor.text)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ThemeColor.fieldBackground, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(option.label.trimmingCharacters(in: CharacterSet(charactersIn: ":")))
                    .accessibilityValue(model.formatter.currency(option.amount))
                    .accessibilityAddTraits(.isButton)
                }
            }
        }

        static func title(_ fill: QuickBudgetFill) -> String {
            switch fill {
            case .assignedLastMonth: "Wie im Vormonat"
            case .outflowsLastMonth: "Ausgaben Vormonat"
            case .averageOutflows: "Ø Ausgaben"
            case .averageOutflowsLastYear: "Ø Vorjahr"
            case .scheduledOutflows: "Geplant"
            case .balanceToZero: "Auf null"
            case .zero: "Null"
            }
        }
    }

    private struct ChipFlow: Layout {
        private struct Line {
            var indices: [Int] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        let spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let lines = lines(subviews, width: proposal.width ?? .infinity)
            let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(lines.count - 1, 0))
            return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            var y = bounds.minY
            for line in lines(subviews, width: bounds.width) {
                var x = bounds.minX
                for index in line.indices {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                    x += size.width + spacing
                }
                y += line.height + spacing
            }
        }

        private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
            var lines = [Line()]
            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(.unspecified)
                if let last = lines.last, !last.indices.isEmpty, last.width + spacing + size.width > width {
                    lines.append(Line())
                }
                let gap = lines[lines.count - 1].indices.isEmpty ? 0 : spacing
                lines[lines.count - 1].indices.append(index)
                lines[lines.count - 1].width += gap + size.width
                lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
            }
            return lines
        }
    }

    private struct BudgetCoverRows: View {
        let controller: BudgetCalloutController
        let form: BudgetAvailableForm

        var body: some View {
            @Bindable var controller = controller
            if form.sources.isEmpty {
                Text(verbatim: BudgetCalloutController.noSources).foregroundStyle(ThemeColor.secondaryText)
            } else {
                Menu {
                    Picker("Decken aus", selection: $controller.coverSourceId) {
                        ForEach(form.sources, id: \.categoryId) { source in
                            Text(verbatim: source.name).tag(source.categoryId)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    LabeledContent("Decken aus") {
                        HStack(spacing: 4) {
                            Text(verbatim: form.source?.name ?? "")
                            Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.medium))
                        }
                        .foregroundStyle(ThemeColor.accent)
                    }
                    .foregroundStyle(ThemeColor.text)
                }
                LabeledContent(controller.remainingLabel) {
                    Text(verbatim: controller.remainingText).monospacedDigit()
                }
                .foregroundStyle(ThemeColor.secondaryText)
                Button(action: controller.coverClicked) {
                    Text(verbatim: controller.coverButtonTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(ThemeColor.selectedText)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(.vertical, 8)
                if let error = form.error {
                    Text(verbatim: error).foregroundStyle(ThemeColor.negative)
                }
            }
        }
    }

    private struct BudgetMoveView: View {
        let controller: BudgetCalloutController
        var focus: FocusState<BudgetSheetField?>.Binding

        var body: some View {
            @Bindable var controller = controller
            Form {
                if let form = controller.availableForm {
                    Section {
                        Picker("Richtung", selection: $controller.moveDirection) {
                            ForEach(BudgetMoveDirection.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        BudgetCategoryPicker(
                            label: "Andere Kategorie", groups: form.others, selection: $controller.moveOtherId,
                            leading: (DefaultCategories.readyToAssignName, controller.readyToAssignCategoryId))
                        BudgetAmountField(label: "Betrag", text: $controller.moveAmount, focus: focus, field: .move)
                        if let error = form.error {
                            Text(verbatim: error).foregroundStyle(ThemeColor.negative)
                        }
                    }
                    Section {
                        Button(action: controller.moveClicked) {
                            Text(BudgetAvailableMode.move.title)
                                .fontWeight(.semibold)
                                .foregroundStyle(ThemeColor.selectedText)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .listRowInsets(.vertical, 8)
                    }
                }
            }
            .modifier(ReportsFormHeight())
            .navigationTitle("Geld verschieben")
        }
    }

    private struct BudgetGroupSheet: View {
        let model: BudgetViewModel
        let form: BudgetCategoryForm
        var focus: FocusState<BudgetSheetField?>.Binding

        var body: some View {
            @Bindable var controller = model.callouts
            Form {
                Section("Name") {
                    TextField("Name", text: $controller.categoryName)
                        .focused(focus, equals: .name)
                        .submitLabel(.done)
                        .onSubmit(controller.categoryDone)
                }
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

    private struct BudgetAssignSheet: View {
        let controller: BudgetCalloutController
        let form: BudgetAssignForm
        var focus: FocusState<BudgetSheetField?>.Binding

        var body: some View {
            @Bindable var controller = controller
            Form {
                Section {
                    BudgetCategoryPicker(
                        label: "Kategorie", groups: form.categories, selection: $controller.assignCategoryId)
                    BudgetAmountField(label: "Betrag", text: $controller.assignAmount, focus: focus, field: .assign)
                } footer: {
                    Text(verbatim: form.freeText)
                }
                if let error = form.error {
                    Text(verbatim: error).foregroundStyle(ThemeColor.negative)
                }
            }
            .navigationTitle("In eine Kategorie")
            .navigationSubtitle(form.monthTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark", role: .close, action: controller.assignCancelled)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zuweisen", systemImage: "checkmark", role: .confirm, action: controller.assignClicked)
                }
            }
            .onAppear { focus.wrappedValue = .assign }
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
                    .keyboardType(.decimalPad)
                    .focused(focus, equals: field)
            }
        }
    }
#endif

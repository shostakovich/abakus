#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    enum TransactionSheetPage: Hashable {
        case choice(EditorFieldID)
        case part(String)
    }

    struct TransactionSheet: View {
        let editor: TransactionEditor
        let dialogs: [PresentedDialog]
        @State private var path: [TransactionSheetPage] = []
        @FocusState private var focus: EditorFieldID?

        var body: some View {
            NavigationStack(path: $path) {
                TransactionForm(editor: editor, focus: $focus)
                    .navigationDestination(for: TransactionSheetPage.self) { page in
                        switch page {
                        case .choice(let field): choiceList(field)
                        case .part(let id): TransactionPartForm(editor: editor, id: id, focus: $focus)
                        }
                    }
                    .toolbar { toolbar }
            }
            .modifier(FittedFormSheet())
            .interactiveDismissDisabled(editor.keepsSheet)
            // On the stack, not a page, as it blocks saving.
            .modifier(newCategoryAlert)
            .onAppear {
                if editor.dropDown?.field == .main(.payee) {
                    path = [.choice(.main(.payee))]
                } else if editor.mode == .new {
                    focus = .main(.amount)
                }
            }
            .onChange(of: focus) { old, new in
                if let new {
                    editor.sheetFieldFocused(new)
                } else if let old {
                    editor.sheetFieldUnfocused(old)
                }
            }
            .modifier(DialogAlert(dialogs: dialogs))
        }

        private var newCategoryAlert: NewCategoryAlert {
            NewCategoryAlert(
                form: editor.addCategoryForm, onCancel: { editor.addCategoryCancelled() },
                onCreate: { group, name in
                    editor.addCategoryConfirmed(masterName: group, name: name)
                    if editor.addCategoryForm == nil, case .choice = path.last { path.removeLast() }
                })
        }

        private func choiceList(_ field: EditorFieldID) -> some View {
            let editor = editor
            let current = editor.text(field)
            let newPayee: ((String) -> String?)? = field.column == .payee ? { editor.newPayeeChoice($0) } : nil
            let newCategory: (() -> Void)? = field.column == .category ? { editor.addCategoryClicked(for: field) } : nil
            return ChoiceList(
                title: Self.title(of: field), choices: { editor.choices(for: field, matching: $0) }, current: current,
                formatter: editor.formatter, showsEmoji: field.column == .category,
                initialSearch: editor.dropDown?.field == field ? current : "", newPayee: newPayee,
                onNewCategory: newCategory, onPick: { editor.choose($0, for: field) })
        }

        private static func title(of field: EditorFieldID) -> String {
            switch field.column {
            case .payee: "Empfänger"
            case .category: "Kategorie"
            default: "Konto"
            }
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .cancellationAction) {
                Button(EditorButton.cancel.title, systemImage: "xmark", role: .close) { editor.activate(.cancel) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editor.sheetConfirmButton.title, systemImage: "checkmark", role: .confirm) {
                    focus = nil
                    editor.activate(editor.sheetConfirmButton)
                }
            }
        }
    }

    /// The iPad's sheet takes its form's measured height; inside it the size class can turn compact, so none is read.
    struct FittedFormSheet: ViewModifier {
        var minimumHeight: CGFloat = 0
        @State private var height: CGFloat?

        func body(content: Content) -> some View {
            content
                .environment(\.reportFormHeight, FormHeightReport { height = max($0, minimumHeight) })
                .frame(idealHeight: height)
                .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        }
    }

    struct FormHeightReport {
        let report: @MainActor (CGFloat) -> Void
    }

    extension EnvironmentValues {
        @Entry var reportFormHeight: FormHeightReport?
    }

    /// A scrolling form has no height of its own; in a fitted sheet it reports its content's, its bars included.
    struct ReportsFormHeight: ViewModifier {
        @Environment(\.reportFormHeight) private var reportFormHeight

        func body(content: Content) -> some View {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                } action: { _, new in
                    reportFormHeight?.report(new)
                }
        }
    }

    private struct TransactionForm: View {
        let editor: TransactionEditor
        var focus: FocusState<EditorFieldID?>.Binding
        @State private var isConfirmingDelete = false
        @State private var rowX: CGFloat?
        @State private var formX: CGFloat?

        private var rowInset: CGFloat { FormRowInset.between(rowX, formX) }

        var body: some View {
            Form {
                Section {
                    AmountHero(editor: editor, field: .main(.amount), focus: focus)
                }
                .listRowBackground(Color.clear)
                if let reason = editor.lockReason {
                    Section {
                        Label(reason, systemImage: "lock").foregroundStyle(ThemeColor.secondaryText)
                    }
                }
                Section {
                    ChoiceRow(editor: editor, field: .main(.payee), label: "Empfänger")
                        .measuresGlobalMinX($rowX)
                    if editor.showsCategory {
                        ChoiceRow(editor: editor, field: .main(.category), label: "Kategorie")
                    }
                    ChoiceRow(
                        editor: editor, field: .main(.account), label: "Konto", isLocked: !editor.choosesAccount)
                    dateRow
                    if editor.isScheduled { frequencyRow }
                    MemoField(editor: editor, field: .main(.memo), focus: focus)
                } footer: {
                    if !editor.isSplitMode { moreButtons }
                }
                if editor.isSplitMode { parts }
                if let status = editor.sheetStatus {
                    Section { StatusRow(editor: editor, status: status) }
                }
                if editor.sheetDeletes {
                    Section {
                        Button("Buchung löschen", role: .destructive) { isConfirmingDelete = true }
                            .confirmationDialog(
                                "Buchung löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible
                            ) {
                                Button("Löschen", role: .destructive) {
                                    focus.wrappedValue = nil
                                    editor.activate(.delete)
                                }
                            }
                    }
                }
            }
            .modifier(ReportsFormHeight())
            .measuresGlobalMinX($formX)
            .navigationTitle(editor.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                SheetBottomBar(editor: editor, focus: focus, rowInset: rowInset)
            }
        }

        @ViewBuilder
        private var dateRow: some View {
            let calendar = editor.formatter.dateLocale.calendar
            let range = editor.pickableDates
            if editor.isLocked(.main(.date)) {
                LabeledContent("Datum", value: editor.sheetValue(.main(.date)).text)
            } else {
                DatePicker(
                    "Datum",
                    selection: Binding(
                        get: { editor.clone.date.date(in: calendar) },
                        set: { editor.datePicked(DateWithoutTime($0, in: calendar)) }),
                    in: range.lowerBound.date(in: calendar)...range.upperBound.date(in: calendar),
                    displayedComponents: .date)
            }
        }

        private var frequencyRow: some View {
            Picker(
                "Häufigkeit",
                selection: Binding(get: { editor.frequency ?? .monthly }, set: { editor.frequencyChosen($0) })
            ) {
                ForEach(ScheduledTransactionFrequency.allCases, id: \.self) { frequency in
                    Text(verbatim: frequency.readableName).tag(frequency)
                }
            }
        }

        private var parts: some View {
            Section {
                ForEach(editor.subIds, id: \.self) { id in
                    NavigationLink(value: TransactionSheetPage.part(id)) {
                        PartRow(summary: editor.partSummary(id))
                    }
                    .swipeActions {
                        Button("Löschen", systemImage: "trash", role: .destructive) { delete(id) }
                    }
                }
                Button("Teil hinzufügen", systemImage: "plus") { editor.addSplitLine() }
            } header: {
                Text("Teile")
            } footer: {
                moreButtons
            }
        }

        @ViewBuilder
        private var moreButtons: some View {
            if !editor.sheetMoreButtons.isEmpty {
                HStack(spacing: 12) {
                    ForEach(editor.sheetMoreButtons, id: \.self) { button in
                        Button(button.title) {
                            focus.wrappedValue = nil
                            editor.activate(button)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
                .font(.body)
                .textCase(nil)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }

        private func delete(_ id: String) {
            if focus.wrappedValue?.subId == id { focus.wrappedValue = nil }
            editor.deleteSubRow(id)
        }
    }

    /// Where a form's row content starts, so a bar under the form lines up with its rows.
    private enum FormRowInset {
        static func between(_ row: CGFloat?, _ form: CGFloat?) -> CGFloat {
            guard let row, let form else { return 20 }
            return row - form
        }
    }

    extension View {
        /// A list row lives in a host of its own, so its edge and the form's are both read on the screen.
        fileprivate func measuresGlobalMinX(_ x: Binding<CGFloat?>) -> some View {
            onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }, action: { x.wrappedValue = $0 })
        }
    }

    private struct StatusRow: View {
        let editor: TransactionEditor
        let status: EditorSheetStatus

        var body: some View {
            switch status {
            case .waiting:
                Button {
                    editor.activate(.approve)
                } label: {
                    Label(EditorButton.approve.title, systemImage: "checkmark.circle.fill")
                }
            case .reconciled:
                LabeledContent("Status") {
                    Label("Abgeglichen", systemImage: "lock.fill").foregroundStyle(ThemeColor.secondaryText)
                }
            case .uncleared, .cleared:
                Picker("Status", selection: Binding(get: { status }, set: editor.sheetStatusChosen)) {
                    Text("Vorgemerkt").tag(EditorSheetStatus.uncleared)
                    Text("Gebucht").tag(EditorSheetStatus.cleared)
                }
            }
        }
    }

    private struct PartRow: View {
        let summary: EditorPartSummary

        var body: some View {
            HStack(spacing: 8) {
                Text(verbatim: summary.category)
                    .foregroundStyle(summary.hasCategory ? ThemeColor.text : ThemeColor.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: summary.amount)
                    .monospacedDigit()
                    .foregroundStyle(summary.isInflow ? ThemeColor.positive : ThemeColor.text)
            }
        }
    }

    private struct TransactionPartForm: View {
        let editor: TransactionEditor
        let id: String
        var focus: FocusState<EditorFieldID?>.Binding
        @Environment(\.dismiss) private var dismiss
        @State private var rowX: CGFloat?
        @State private var formX: CGFloat?

        private var rowInset: CGFloat { FormRowInset.between(rowX, formX) }

        var body: some View {
            Form {
                if editor.subIds.contains(id) {
                    Section {
                        AmountHero(editor: editor, field: .sub(id, .amount), focus: focus)
                    }
                    .listRowBackground(Color.clear)
                    Section {
                        ChoiceRow(editor: editor, field: .sub(id, .payee), label: "Empfänger")
                            .measuresGlobalMinX($rowX)
                        ChoiceRow(editor: editor, field: .sub(id, .category), label: "Kategorie")
                        MemoField(editor: editor, field: .sub(id, .memo), focus: focus)
                    }
                    Section {
                        Button("Teil löschen", role: .destructive) {
                            if focus.wrappedValue?.subId == id { focus.wrappedValue = nil }
                            editor.deleteSubRow(id)
                            dismiss()
                        }
                    }
                }
            }
            .modifier(ReportsFormHeight())
            .measuresGlobalMinX($formX)
            .navigationTitle("Teil \((editor.subIds.firstIndex(of: id) ?? 0) + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                SheetBottomBar(editor: editor, focus: focus, rowInset: rowInset)
            }
            .onAppear {
                if editor.partSummary(id).amount.isEmpty { focus.wrappedValue = .sub(id, .amount) }
            }
        }
    }

    /// Inside the sheet, so the iPad's operators never float over the scrim; a hardware keyboard types them itself.
    private struct SheetBottomBar: View {
        static let operatorSize = CGSize(width: 44, height: 32)
        static let fadeHeight: CGFloat = 28

        let editor: TransactionEditor
        var focus: FocusState<EditorFieldID?>.Binding
        let rowInset: CGFloat
        @State private var isKeyboardShown = false

        var body: some View {
            let field = focus.wrappedValue.flatMap { $0.column == .amount ? $0 : nil }
            VStack(spacing: 0) {
                if editor.isSplitMode { remaining }
                if let field, isKeyboardShown {
                    operators(field).padding(.vertical, 8)
                }
            }
            .tracksSoftwareKeyboard($isKeyboardShown)
        }

        private var remaining: some View {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text("Noch aufzuteilen")
                    Spacer()
                    Text(verbatim: editor.remainingText)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(editor.remainingAmount == 0 ? ThemeColor.secondaryText : ThemeColor.negative)
                }
                .padding(.horizontal, rowInset)
                .padding(.vertical, 12)
            }
            .background(.bar)
            // The form fades out above the bar, so a card's edge never peeks over it as a sliver.
            .background(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: ThemeColor.groupedBackground.opacity(0), location: 0),
                        .init(color: ThemeColor.groupedBackground, location: 0.5),
                    ], startPoint: .top, endPoint: .bottom
                )
                .frame(height: Self.fadeHeight)
                .offset(y: -Self.fadeHeight)
                .allowsHitTesting(false)
            }
        }

        private func operators(_ field: EditorFieldID) -> some View {
            HStack(spacing: 8) {
                ForEach(["+", "−", "×", "÷"], id: \.self) { symbol in
                    Button {
                        editor.sheetTextChanged(field, to: editor.text(field) + symbol)
                    } label: {
                        key(Text(verbatim: symbol))
                    }
                    .accessibilityLabel(Self.operatorName(symbol))
                }
                Spacer()
                Button {
                    focus.wrappedValue = nil
                } label: {
                    key(Text(Image(systemName: "keyboard.chevron.compact.down")))
                }
                .accessibilityLabel("Tastatur ausblenden")
            }
            .buttonStyle(.glass)
            .padding(.horizontal, 16)
        }

        private func key(_ text: Text) -> some View {
            text
                .font(.title3.weight(.medium))
                .frame(width: Self.operatorSize.width, height: Self.operatorSize.height)
        }

        private static func operatorName(_ symbol: String) -> String {
            switch symbol {
            case "+": "Plus"
            case "−": "Minus"
            case "×": "Mal"
            default: "Geteilt durch"
            }
        }
    }

    private struct AmountHero: View {
        let editor: TransactionEditor
        let field: EditorFieldID
        var focus: FocusState<EditorFieldID?>.Binding
        @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 44

        var body: some View {
            let isLocked = editor.isLocked(field)
            let isInflow = editor.isInflow(field)
            let locale = editor.formatter.currencyLocale
            let ink = isInflow ? ThemeColor.positive : ThemeColor.text
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button {
                    editor.sheetSignToggled(field)
                } label: {
                    Image(systemName: isInflow ? "plus" : "minus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(isInflow ? ThemeColor.positive : ThemeColor.accent)
                .disabled(isLocked)
                .accessibilityLabel(isInflow ? "Einnahme" : "Ausgabe")
                .accessibilityHint(isInflow ? "Macht eine Ausgabe daraus" : "Macht eine Einnahme daraus")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if locale.symbolOnLeft { symbol(locale.currencySymbol) }
                    TextField(
                        "0\(locale.decimalSeparator)00",
                        text: Binding(get: { editor.text(field) }, set: { editor.sheetTextChanged(field, to: $0) })
                    )
                    .font(.system(size: amountSize, weight: .semibold))
                    .keyboardType(keyboard)
                    .fixedSize()
                    .foregroundStyle(ink)
                    .focused(focus, equals: field)
                    .disabled(isLocked)
                    .accessibilityLabel("Betrag")
                    if !locale.symbolOnLeft { symbol(locale.currencySymbol) }
                }
                .font(.system(size: amountSize, weight: .semibold))
                .monospacedDigit()
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.vertical, 4)
        }

        /// The iPad's number pad floats over the sheet's title without + − × ÷, so it takes the docked keyboard.
        private var keyboard: UIKeyboardType {
            UIDevice.current.userInterfaceIdiom == .pad ? .numbersAndPunctuation : .decimalPad
        }

        private func symbol(_ text: String) -> some View {
            Text(verbatim: text).foregroundStyle(ThemeColor.secondaryText)
        }
    }

    private struct ChoiceRow: View {
        static let placeholder = "Wählen"

        let editor: TransactionEditor
        let field: EditorFieldID
        let label: String
        var isLocked = false

        /// A prompt that only repeats the label gives way to the placeholder.
        private var prompt: String {
            let prompt = editor.prompt(field)
            return prompt.isEmpty || prompt == label ? Self.placeholder : prompt
        }

        var body: some View {
            let value = editor.sheetValue(field)
            let isEmpty = value.text.isEmpty
            let isReadOnly = isLocked || editor.isLocked(field)
            let content = LabeledContent(label) {
                HStack(spacing: 4) {
                    if value.isTransfer {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.footnote.weight(.medium))
                            .accessibilityLabel("Umbuchung zu")
                    }
                    Text(verbatim: isEmpty ? prompt : value.text)
                        .lineLimit(1)
                }
                .foregroundStyle(isEmpty || isReadOnly ? ThemeColor.secondaryText : ThemeColor.text)
            }
            if isReadOnly {
                content
            } else {
                NavigationLink(value: TransactionSheetPage.choice(field)) { content }
            }
        }
    }

    private struct MemoField: View {
        let editor: TransactionEditor
        let field: EditorFieldID
        var focus: FocusState<EditorFieldID?>.Binding

        var body: some View {
            LabeledContent("Memo") {
                TextField(
                    "Memo", text: Binding(get: { editor.text(field) }, set: { editor.sheetTextChanged(field, to: $0) }),
                    prompt: Text("Optional")
                )
                .multilineTextAlignment(.trailing)
                .focused(focus, equals: field)
                .submitLabel(.done)
            }
        }
    }
#endif

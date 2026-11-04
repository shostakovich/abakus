#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct RegisterScreen: View {
        let register: RegisterViewModel
        let dialogs: [PresentedDialog]
        var onEditAccount: (() -> Void)?
        @Environment(\.horizontalSizeClass) private var sizeClass
        @FocusState private var isSearchFocused: Bool
        @State private var isConfirmingDelete = false
        @State private var payeeName = ""
        @State private var width: CGFloat?
        @State private var tableLeading: CGFloat = RegisterList.rowInsets.leading
        @ScaledMetric(relativeTo: .subheadline) private var textScale: CGFloat = 1

        private var table: RegisterTouchTable? {
            guard sizeClass == .regular else { return nil }
            let table = RegisterTouchTable(visibleColumns: register.visibleColumns, scale: textScale)
            let insets = RegisterList.rowInsets.leading + RegisterList.rowInsets.trailing
            guard let width else { return table }
            return table.fits(in: width - insets) ? table : nil
        }

        var body: some View {
            let search = register.search
            let table = table
            // Read here, so a change re-renders the screen and reaches the sheets' bindings.
            let statementForm = register.reconciliation.statementForm
            let showsScheduler = register.isSchedulerVisible
            RegisterList(register: register, table: table, pickingTableLeading: $tableLeading)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
                .safeAreaBar(edge: .top, spacing: 0) {
                    // The phone's suggestions take the screen and would start below the header's inset.
                    if sizeClass == .regular || search.dropDown == nil {
                        RegisterHeaderView(register: register, table: table, columnIndent: columnIndent)
                    }
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    if let footer = register.reconciliation.footer {
                        ReconciliationBar(reconciliation: register.reconciliation, footer: footer)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if sizeClass == .regular && isSearchFocused && search.dropDown != nil {
                        RegisterSuggestionPanel(search: search)
                            .padding(.trailing, 16)
                            .padding(.top, 4)
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(LeadingTitle(title: title, isOn: sizeClass == .regular && !register.isPicking))
                .navigationBarBackButtonHidden(register.isPicking)
                .toolbar { toolbar }
                .searchable(
                    text: Binding(get: { search.textBesideTokens }, set: { search.tokenBoxChanged($0) }),
                    tokens: searchTokens, placement: searchPlacement, prompt: search.prompt
                ) { token in
                    Label(token.title, systemImage: token.systemImage)
                }
                .searchSuggestions {
                    if sizeClass == .compact { RegisterSearchSuggestions(search: search) }
                }
                .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                    guard sizeClass == .regular, isSearchFocused, search.dropDown != nil else { return .ignored }
                    search.moveHighlight(by: press.key == .downArrow ? 1 : -1)
                    return .handled
                }
                .searchFocused($isSearchFocused)
                .onSubmit(of: .search) { search.submitted() }
                .onChange(of: isSearchFocused) { _, focused in search.focusChanged(focused) }
                .onChange(of: search.focusRequest) { isSearchFocused = true }
                .sheet(isPresented: isTimeframeShown) {
                    TimeframeSheet(search: search)
                }
                .sheet(item: statementSheet(statementForm)) { form in
                    StatementSheet(register: register, form: form, dialogs: dialogs)
                }
                .sheet(isPresented: schedulerSheet(showsScheduler)) {
                    ScheduledSheet(register: register, dialogs: dialogs, isCompact: sizeClass == .compact)
                }
                .alert(
                    scheduledCallout?.title ?? "", isPresented: isScheduledCalloutShown, presenting: scheduledCallout
                ) { _ in
                    Button("Zeigen") {
                        register.closePopup()
                        if !register.isSchedulerVisible { register.scheduledToggleClicked() }
                    }
                    Button("OK", role: .cancel) { register.closePopup() }
                } message: { callout in
                    Text(TextMarkup.plain(callout.touchMessage))
                }
                .alert(
                    "Gleiche Empfänger umbenennen", isPresented: isRenamingPayee, presenting: register.renamePayeeForm
                ) { _ in
                    TextField("Empfänger", text: $payeeName)
                    Button("Abbrechen", role: .cancel) { register.renamePayeeCancelled() }
                    Button("Umbenennen") { register.renamePayeeConfirmed(payeeName) }
                } message: { form in
                    Text(form.description)
                }
                .onChange(of: register.renamePayeeForm) { _, form in payeeName = form?.currentName ?? "" }
                .alert(
                    Text(TextMarkup.plain(register.adjustmentHelp?.message ?? "")), isPresented: isAdjustmentHelpShown
                ) {
                    Button("OK", role: .cancel, action: register.adjustmentHelpDismissed)
                }
        }

        private var columnIndent: CGFloat {
            register.isPicking ? max(tableLeading - RegisterList.rowInsets.leading, 0) : 0
        }

        private var title: String {
            guard register.isPicking else { return register.accountName }
            let count = register.selection.count
            return count == 0 ? "Auswählen" : "\(count) ausgewählt"
        }

        /// The phone keeps the field in view, as it shows the filter.
        private var searchPlacement: SearchFieldPlacement {
            sizeClass == .compact ? .navigationBarDrawer(displayMode: .always) : .toolbar
        }

        private var searchTokens: Binding<[RegisterSearchToken]> {
            let search = register.search
            return Binding {
                search.showsApprovalToken ? [.approvals] : []
            } set: { tokens in
                if tokens.isEmpty { search.approvalTokenRemoved() }
            }
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if register.isPicking {
                ToolbarItem(placement: .topBarLeading) {
                    Button(register.isAllSelected ? "Keine" : "Alle") {
                        register.performMenuAction(.toggleSelectAll)
                    }
                    .keyboardShortcut(register.isAllSelected || isSearchFocused ? nil : KeyboardShortcut("a"))
                    .disabled(register.transactionIds.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { register.performMenuAction(.togglePicking) }
                }
                RegisterPickingBar(register: register, isConfirmingDelete: $isConfirmingDelete)
            } else {
                if sizeClass == .regular {
                    DefaultToolbarItem(kind: .search, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) { viewMenu }
            }
        }

        private var viewMenu: some View {
            Menu {
                if !register.isReconciling {
                    Button("Geplant", systemImage: "calendar.badge.clock") {
                        register.scheduledToggleClicked()
                    }
                }
                RegisterMenuItemsView(
                    items: register.touchViewMenu(showsColumns: sizeClass == .regular),
                    perform: register.performMenuAction)
                if let onEditAccount {
                    Divider()
                    Button("Konto bearbeiten …", systemImage: "pencil", action: onEditAccount)
                }
            } label: {
                Label("Ansicht", systemImage: "ellipsis")
            }
        }

        private var isTimeframeShown: Binding<Bool> {
            Binding {
                register.popup == .timeframe
            } set: { shown in
                if !shown && register.popup == .timeframe { register.search.timeframeCancelled() }
            }
        }

        private func statementSheet(_ form: ReconciliationStatementForm?) -> Binding<ReconciliationStatementForm?> {
            Binding {
                form
            } set: { form in
                if form == nil { register.reconciliation.statementCancelled() }
            }
        }

        private func schedulerSheet(_ isShown: Bool) -> Binding<Bool> {
            Binding {
                isShown
            } set: { shown in
                if !shown && register.isSchedulerVisible { register.scheduledToggleClicked() }
            }
        }

        private var scheduledCallout: RegisterScheduledCallout? {
            if case .scheduledCallout(let callout) = register.popup { callout } else { nil }
        }

        private var isScheduledCalloutShown: Binding<Bool> {
            Binding {
                scheduledCallout != nil
            } set: { shown in
                if !shown && scheduledCallout != nil { register.closePopup() }
            }
        }

        private var isAdjustmentHelpShown: Binding<Bool> {
            Binding {
                register.adjustmentHelp != nil
            } set: { shown in
                if !shown { register.adjustmentHelpDismissed() }
            }
        }

        private var isRenamingPayee: Binding<Bool> {
            Binding {
                register.renamePayeeForm != nil
            } set: { shown in
                if !shown && register.renamePayeeForm != nil { register.renamePayeeCancelled() }
            }
        }
    }

    private struct RegisterPickingBar: ToolbarContent {
        let register: RegisterViewModel
        @Binding var isConfirmingDelete: Bool

        var body: some ToolbarContent {
            let actions = register.pickingActions
            let ids = actions.ids
            ToolbarItemGroup(placement: .bottomBar) {
                Button(actions.status.statusTitle) { register.performMenuAction(actions.status, on: ids) }
                    .disabled(!actions.isStatusEnabled)
                Menu("Kategorie") {
                    RegisterMenuItemsView(items: actions.categories) { register.performMenuAction($0, on: ids) }
                }
                .disabled(actions.categories.isEmpty)
                Button("Löschen", role: .destructive) { isConfirmingDelete = true }
                    .tint(ThemeColor.negative)
                    .disabled(!actions.canDelete)
                    .confirmationDialog(
                        actions.deleteQuestion, isPresented: $isConfirmingDelete, titleVisibility: .visible
                    ) {
                        Button("Löschen", role: .destructive) { register.performMenuAction(.delete, on: ids) }
                    }
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Menu("Mehr", systemImage: "ellipsis") {
                    if let total = register.selectedTotal {
                        Text(verbatim: "\(total.title): \(total.amountText)")
                        Divider()
                    }
                    RegisterMenuItemsView(items: actions.menu) { register.performMenuAction($0, on: ids) }
                }
                .disabled(ids.isEmpty)
            }
        }
    }

    /// The iPad's bar moves a centred title aside while the search is open, so the title leads in every state.
    private struct LeadingTitle: ViewModifier {
        let title: String
        let isOn: Bool

        func body(content: Content) -> some View {
            if isOn {
                content
                    .toolbar(removing: .title)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Text(verbatim: title)
                                .font(.headline)
                                .lineLimit(1)
                                .fixedSize()
                                .accessibilityAddTraits(.isHeader)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
            } else {
                content
            }
        }
    }

    enum RegisterSearchToken: Identifiable {
        case approvals

        var id: Self { self }
        var title: String { RegisterSearchController.approvalTokenTitle }
        var systemImage: String { "checkmark.circle" }
    }

    private struct RegisterSearchSuggestions: View {
        let search: RegisterSearchController

        var body: some View {
            ForEach(search.touchSuggestionGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.rows) { row in
                        Button {
                            search.pickSuggestion(at: row.index)
                        } label: {
                            SuggestionLabel(row: row).foregroundStyle(ThemeColor.text)
                        }
                    }
                }
            }
        }
    }

    /// The system's popover on the iPad drops section headers and lets the screen show through.
    private struct RegisterSuggestionPanel: View {
        static let width: CGFloat = 380
        static let maxHeight: CGFloat = 560

        let search: RegisterSearchController
        @State private var contentHeight: CGFloat = 0

        var body: some View {
            let groups = search.touchSuggestionGroups
            let highlighted = search.dropDown?.highlighted
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.title) { group in
                        Text(verbatim: group.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ThemeColor.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.rows) { row in
                            Button {
                                search.pickSuggestion(at: row.index)
                            } label: {
                                SuggestionLabel(row: row)
                                    .foregroundStyle(ThemeColor.text)
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .background(
                                        highlighted == row.index ? ThemeColor.selection : .clear,
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectHidden(true, for: .all)
            // The panel floats over the header bar, whose inset and edge blur are not its own.
            .ignoresSafeArea()
            .frame(width: Self.width, height: min(contentHeight, Self.maxHeight))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 6)
        }
    }

    private struct SuggestionLabel: View {
        let row: RegisterTouchSuggestion
        @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 96

        var body: some View {
            if row.isScope {
                Label(row.field, systemImage: "magnifyingglass").lineLimit(1)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: row.field)
                        .foregroundStyle(ThemeColor.secondaryText)
                        .frame(width: labelWidth, alignment: .leading)
                    if row.isTransfer {
                        Image(systemName: StatusSymbol.transfer.name).accessibilityLabel(StatusSymbol.transfer.label)
                    }
                    Text(verbatim: row.value)
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
            }
        }
    }
#endif

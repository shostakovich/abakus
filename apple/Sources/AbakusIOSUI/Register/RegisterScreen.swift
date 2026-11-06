#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct RegisterScreen: View {
        let register: RegisterViewModel
        let dialogs: [PresentedDialog]
        @Environment(\.horizontalSizeClass) private var sizeClass
        @FocusState private var isSearchFocused: Bool
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
                    RegisterHeaderView(register: register, table: table, columnIndent: columnIndent)
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    if let footer = register.reconciliation.footer {
                        ReconciliationBar(reconciliation: register.reconciliation, footer: footer)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(LeadingTitle(title: title, isOn: sizeClass == .regular && !register.isPicking))
                .navigationBarBackButtonHidden(register.isPicking)
                .toolbar { toolbar }
                .searchable(
                    text: Binding(get: { search.text }, set: { search.boxChanged($0) }), placement: searchPlacement,
                    prompt: search.prompt
                )
                .searchFocused($isSearchFocused)
                .onChange(of: isSearchFocused) { _, focused in search.focusChanged(focused) }
                .onChange(of: search.focusRequest) { isSearchFocused = true }
                .sheet(item: statementSheet(statementForm)) { form in
                    StatementSheet(register: register, form: form, dialogs: dialogs)
                }
                .sheet(isPresented: schedulerSheet(showsScheduler)) {
                    ScheduledSheet(register: register, dialogs: dialogs, isCompact: sizeClass == .compact)
                }
                .sheet(isPresented: closedAccountsSheet) {
                    ClosedAccountsSheet(register: register)
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
                RegisterPickingBar(register: register)
            } else {
                if sizeClass == .regular {
                    DefaultToolbarItem(kind: .search, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) { viewMenu }
            }
        }

        private var viewMenu: some View {
            Menu {
                RegisterMenuItemsView(
                    items: register.touchViewMenu(showsColumns: sizeClass == .regular),
                    perform: register.performMenuAction)
            } label: {
                Label("Ansicht", systemImage: "ellipsis")
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

        private var closedAccountsSheet: Binding<Bool> {
            Binding {
                register.isClosedAccountsListShown
            } set: { shown in
                if !shown { register.closedAccountsDismissed() }
            }
        }
    }

    private struct RegisterPickingBar: ToolbarContent {
        let register: RegisterViewModel

        var body: some ToolbarContent {
            let actions = register.pickingActions
            let ids = actions.ids
            ToolbarItemGroup(placement: .bottomBar) {
                Menu("Kategorie") {
                    RegisterMenuItemsView(items: actions.categories) { register.performMenuAction($0, on: ids) }
                }
                .disabled(actions.categories.isEmpty)
                Button("Löschen", role: .destructive) { register.performMenuAction(.delete, on: ids) }
                    .tint(ThemeColor.negative)
                    .disabled(!actions.canDelete)
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
#endif

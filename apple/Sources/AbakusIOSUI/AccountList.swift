#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct AccountList: View {
        let model: SidebarViewModel
        let accounts: AccountsController
        let register: RegisterViewModel

        var body: some View {
            let approvals = register.approvalCount
            List {
                Section {
                    if approvals > 0 {
                        Button(action: register.showApprovals) {
                            HStack {
                                AccountRowLabel(title: RegisterViewModel.approvalsTitle(approvals)) {
                                    AccountSymbol(name: "checkmark.circle")
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.forward")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink(value: SidebarSelection.allAccounts) {
                        AccountRowLabel(title: Account.allAccountsName) {
                            AccountSymbol(name: "building.columns")
                        }
                    }
                }
                AccountGroupSections(model: model)
            }
            .listStyle(.insetGrouped)
            .readableListWidth()
            .navigationTitle("Konten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: accounts.addAccountClicked) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Konto")
                        }
                    }
                    .accessibilityLabel(AddAccountForm.title)
                }
            }
            .scrollsUnderDock()
        }
    }

    private struct AccountGroupSections: View {
        let model: SidebarViewModel

        var body: some View {
            ForEach(model.groupPanels) { panel in
                Section {
                    if !panel.isCollapsed {
                        ForEach(panel.rows) { account in
                            NavigationLink(value: SidebarSelection.account(account.id)) { AccountRow(row: account) }
                        }
                        .onMove { model.moveAccount(in: panel.group, from: $0, to: $1) }
                    }
                } header: {
                    AccountGroupHeader(model: model, panel: panel)
                }
            }
        }
    }

    private struct AccountGroupHeader: View {
        let model: SidebarViewModel
        let panel: SidebarGroupPanel

        var body: some View {
            Button {
                withAnimation(.smooth) { model.setGroup(panel.group, expanded: panel.isCollapsed) }
            } label: {
                HStack(spacing: 8) {
                    Text(panel.title).lineLimit(1).layoutPriority(1)
                    if let badge = panel.headerBadge { AccountBadge(badge: badge) }
                    Spacer(minLength: 8)
                    AccountAmount(text: panel.totalText, amount: panel.total, isTotal: true)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ThemeColor.accent)
                        .rotationEffect(.degrees(panel.isCollapsed ? -90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ThemeColor.secondaryText)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(panel.isCollapsed ? "Eingeklappt" : "Ausgeklappt")
            .accessibilityHint(panel.isCollapsed ? "Zeigt die Konten der Gruppe." : "Blendet die Konten aus.")
        }
    }

    private struct AccountRow: View {
        let row: SidebarAccountRow

        var body: some View {
            HStack(spacing: 8) {
                AccountRowLabel(title: row.label) {
                    if let emoji = row.emoji {
                        Text(verbatim: emoji)
                    } else {
                        AccountSymbol(name: row.motif.symbolName)
                    }
                }
                .layoutPriority(1)
                if let badge = row.badge { AccountBadge(badge: badge).fixedSize() }
                Spacer(minLength: 8)
                AccountAmount(text: row.balanceText, amount: row.balance)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: row.name))
            .accessibilityValue(Text(verbatim: row.accessibilityValue))
        }
    }

    /// The symbol or emoji in a column of fixed width, so every name of the list starts at one edge.
    private struct AccountRowLabel<Icon: View>: View {
        let title: String
        @ViewBuilder let icon: Icon
        @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 30

        var body: some View {
            HStack(spacing: 12) {
                icon.frame(width: iconWidth).accessibilityHidden(true)
                Text(verbatim: title)
                    .foregroundStyle(ThemeColor.text)
                    .lineLimit(1)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
        }
    }

    private struct AccountSymbol: View {
        let name: String

        var body: some View {
            Image(systemName: name).foregroundStyle(ThemeColor.accent)
        }
    }

    private struct AccountAmount: View {
        let text: String
        let amount: Decimal
        var isTotal = false

        var body: some View {
            Text(text)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(amount < 0 ? AnyShapeStyle(ThemeColor.negative) : style)
        }

        private var style: AnyShapeStyle {
            isTotal ? AnyShapeStyle(ThemeColor.secondaryText) : AnyShapeStyle(ThemeColor.text)
        }
    }

    /// The register's chip colours, with a symbol, so the colour is not the only sign of what waits.
    private struct AccountBadge: View {
        let badge: SidebarBadge

        var body: some View {
            Label {
                Text(verbatim: badge.text).monospacedDigit()
            } icon: {
                Image(systemName: symbol)
            }
            .labelStyle(BadgeLabelStyle())
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: badge.summary))
        }

        private var symbol: String {
            switch badge.kind {
            case .needsCategory: "questionmark.circle.fill"
            case .forReview: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }

        private var tint: Color {
            switch badge.kind {
            case .needsCategory: ThemeColor.warning
            case .forReview: ThemeColor.accent
            case .error: ThemeColor.negative
            }
        }
    }

    private struct BadgeLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 3) {
                configuration.icon
                configuration.title
            }
        }
    }

    extension View {
        func readableListWidth() -> some View {
            modifier(ReadableListWidth())
        }
    }

    private struct ReadableListWidth: ViewModifier {
        private static let maxWidth: CGFloat = 720
        private static let minimumMargin: CGFloat = 20
        @State private var margin: CGFloat?

        func body(content: Content) -> some View {
            content
                .contentMargins(.horizontal, margin, for: .scrollContent)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                    let wide = (width - Self.maxWidth) / 2
                    margin = wide > Self.minimumMargin ? wide : nil
                }
        }
    }
#endif

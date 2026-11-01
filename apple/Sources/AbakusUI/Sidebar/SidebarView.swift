import AbakusCore
import SwiftUI

struct SidebarGroupAnchorKey: PreferenceKey {
    static let defaultValue: [SidebarGroup: Anchor<CGRect>] = [:]

    static func reduce(value: inout [SidebarGroup: Anchor<CGRect>], nextValue: () -> [SidebarGroup: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

public struct SidebarView: View {
    let model: SidebarViewModel
    var onAddAccount: () -> Void = {}
    var onEditAccount: (String) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme

    public init(
        model: SidebarViewModel, onAddAccount: @escaping () -> Void = {},
        onEditAccount: @escaping (String) -> Void = { _ in }
    ) {
        self.model = model
        self.onAddAccount = onAddAccount
        self.onEditAccount = onEditAccount
    }

    /// Where a popover stands while its sidebar row or header is not laid out: below the toolbar.
    static func fallbackAnchor(in proxy: GeometryProxy) -> CGRect {
        CGRect(x: 0, y: proxy.safeAreaInsets.top, width: 150, height: 0)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                sections
                ForEach(model.groupPanels) { panel in
                    Section(isExpanded: expansion(of: panel.group)) {
                        ForEach(panel.rows) { row in
                            SidebarAccountRowView(row: row, showsBalance: model.isFullView)
                                .tag(SidebarSelection.account(row.id))
                                .id(SidebarSelection.account(row.id))
                                .onSecondaryClick { _ in
                                    onEditAccount(row.id)
                                    return []
                                }
                                .anchorPreference(key: SidebarRowAnchorKey.self, value: .bounds) { [row.id: $0] }
                        }
                    } header: {
                        SidebarGroupHeader(panel: panel, showsTotal: model.isFullView)
                            .anchorPreference(key: SidebarGroupAnchorKey.self, value: .bounds) { [panel.group: $0] }
                    }
                }
            }
            .onChange(of: model.revealRequest) { _, request in
                if let request { proxy.scrollTo(request.selection) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter(model: model, onAddAccount: onAddAccount)
        }
        .environment(\.sidebarColors, colors)
        .environment(\.colorScheme, .dark)
        .background(colors.background)
        .toolbar(removing: .sidebarToggle)
    }

    @ViewBuilder
    private var sections: some View {
        let titles = model.sectionTitles
        Label {
            Text(titles.budget).lineLimit(1).foregroundStyle(colors.content)
        } icon: {
            SidebarIcon(systemName: "chart.pie.fill")
        }
        .tag(SidebarSelection.budget)
        .id(SidebarSelection.budget)
        Label {
            Text(titles.allAccounts).lineLimit(1).foregroundStyle(colors.content)
        } icon: {
            SidebarIcon(systemName: "building.columns.fill")
        }
        .tag(SidebarSelection.allAccounts)
    }

    private var colors: SidebarColors { SidebarColors(colorScheme) }

    private var selection: Binding<SidebarSelection?> {
        Binding {
            model.navigation.selection
        } set: { selection in
            if let selection { model.select(selection) }
        }
    }

    private func expansion(of group: SidebarGroup) -> Binding<Bool> {
        Binding {
            !model.collapsedGroups.contains(group)
        } set: { expanded in
            model.setGroup(group, expanded: expanded)
        }
    }
}

/// The narrow mode is a width of its own; the wide one stays resizable.
struct SidebarWidth: ViewModifier {
    let isFullView: Bool

    func body(content: Content) -> some View {
        content.navigationSplitViewColumnWidth(
            min: isFullView ? 220 : 150, ideal: isFullView ? 260 : 150, max: isFullView ? 400 : 150)
    }
}

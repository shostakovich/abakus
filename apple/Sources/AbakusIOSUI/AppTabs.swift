#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    /// The tab bar is drawn here, as the system's leaves no room for a "+" of its own beside it.
    struct AppTabs: View {
        let model: AppModel
        @Bindable var navigation: TouchNavigation
        @State private var dock = DockState()
        @State private var isKeyboardShown = false

        var body: some View {
            TabView(selection: Binding(get: { navigation.tab }, set: navigation.select)) {
                Tab(value: AppTab.budget) {
                    NavigationStack {
                        BudgetScreen(model: model.budget, dialogs: model.presentedDialogs)
                    }
                    .toolbarVisibility(.hidden, for: .tabBar)
                }
                Tab(value: AppTab.accounts) {
                    NavigationStack(path: Binding(get: { navigation.accountPath }, set: navigation.showAccounts)) {
                        AccountList(model: model.sidebar, accounts: model.accounts, register: model.register)
                            .navigationDestination(for: SidebarSelection.self) { _ in
                                if model.showsRegister { RegisterDetail(model: model) }
                            }
                    }
                    .toolbarVisibility(.hidden, for: .tabBar)
                }
                Tab(value: AppTab.settings) {
                    NavigationStack(path: settingsPath) {
                        SettingsScreen(model: model.syncSettings)
                            .navigationDestination(for: PayeeRoute.self) { route in
                                if let payees = model.payeeSettings {
                                    PayeePage(
                                        model: payees, route: route, path: settingsPath,
                                        isPicking: $navigation.isPickingPayees)
                                }
                            }
                    }
                    .toolbarVisibility(.hidden, for: .tabBar)
                }
            }
            .tabViewStyle(.tabBarOnly)
            .environment(\.dock, dock)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if !hidesDock {
                    Dock(model: model, navigation: navigation, state: dock, onAdd: navigation.addTransactionClicked)
                        // The glass would stay bright under a sheet's dimming, so the dock fades back with the screen.
                        .opacity(navigation.showsSheet ? 0.4 : 1)
                        .animation(.smooth(duration: 0.3), value: navigation.showsSheet)
                }
            }
            // The system's tab bar stays behind the keyboard instead of riding on it.
            .tracksSoftwareKeyboard($isKeyboardShown)
            .onChange(of: hidesDock, initial: true) { _, hides in dock.isHidden = hides }
            .onChange(of: navigation.tab) { dock.expand() }
        }

        private var hidesDock: Bool { isKeyboardShown || navigation.barTakesDocksPlace || popoverReachesDock }

        /// The category's popover may run as tall as the screen, and the dock would show at its foot.
        private var popoverReachesDock: Bool {
            navigation.tab == .budget && model.budget.showsCategoryPopover
        }

        private var settingsPath: Binding<[PayeeRoute]> {
            // A method reference here crashes the Swift 6.3 compiler of CI's Xcode 26.
            Binding(get: { navigation.settingsPath }, set: { navigation.showSettings($0) })
        }
    }

    private struct DockTab: Identifiable {
        let tab: AppTab
        let title: String
        let symbol: String

        var id: AppTab { tab }

        static let all = [
            DockTab(tab: .budget, title: "Budget", symbol: "chart.pie"),
            DockTab(tab: .accounts, title: "Konten", symbol: "building.columns"),
            DockTab(tab: .settings, title: "Einstellungen", symbol: "gearshape"),
        ]
    }

    private struct Dock: View {
        static let height: CGFloat = 62
        /// As far from the screen's bottom edge as the system's tab bar, also where the home indicator sits.
        static let screenEdgeGap: CGFloat = 21
        private static let maxWidth: CGFloat = 440

        let model: AppModel
        let navigation: TouchNavigation
        let state: DockState
        let onAdd: (_ transfer: Bool) -> Void
        @State private var bottomInset: CGFloat = 0
        @Namespace private var glass

        var body: some View {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if state.isMinimized {
                        minimizedTab
                        Spacer(minLength: 0)
                    } else {
                        tabs
                    }
                    AddTransactionButton(register: model.register, size: Self.height, onAdd: onAdd)
                }
                .frame(maxWidth: Self.maxWidth)
            }
            .animation(.smooth(duration: 0.3), value: state.isMinimized)
            .padding(.horizontal, 20)
            .padding(.bottom, bottomInset > 0 ? Self.screenEdgeGap - bottomInset : Self.screenEdgeGap)
            .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) { inset in
                bottomInset = inset
                state.clearance = max(Self.height + Self.screenEdgeGap - inset, 0) + DockState.contentGap
            }
        }

        private var tabs: some View {
            HStack(spacing: 0) {
                ForEach(DockTab.all) { item($0) }
            }
            .padding(4)
            .frame(height: Self.height)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("tabs", in: glass)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
        }

        private var minimizedTab: some View {
            let shown = DockTab.all.first { $0.tab == navigation.tab } ?? DockTab.all[0]
            return Button(action: state.expand) {
                Image(systemName: shown.symbol)
                    .symbolVariant(.fill)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ThemeColor.accent)
                    .frame(width: Self.height, height: Self.height)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID("tabs", in: glass)
            .accessibilityLabel(shown.title)
            .accessibilityHint("Zeigt alle Tabs.")
        }

        private func item(_ item: DockTab) -> some View {
            let isSelected = navigation.tab == item.tab
            return Button {
                navigation.select(item.tab)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: item.symbol)
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 20, weight: .medium))
                        .frame(height: 26)
                        .overlay(alignment: .topTrailing) { badge(of: item.tab) }
                    Text(item.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? ThemeColor.accent : ThemeColor.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected { Capsule().fill(.quaternary) }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .accessibilityValue(accessibilityValue(of: item.tab))
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityShowsLargeContentViewer {
                Label(item.title, systemImage: item.symbol)
            }
        }

        @ViewBuilder
        private func badge(of tab: AppTab) -> some View {
            switch tab {
            case .accounts:
                let count = model.register.approvalCount
                if count > 0 { BadgeCount(count: count).offset(x: 12, y: -6) }
            case .settings:
                if model.sidebar.cloudStatus.needsAttention {
                    Circle().fill(ThemeColor.negative).frame(width: 8, height: 8).offset(x: 3, y: -1)
                }
            case .budget:
                EmptyView()
            }
        }

        private func accessibilityValue(of tab: AppTab) -> String {
            switch tab {
            case .accounts:
                let count = model.register.approvalCount
                return count > 0 ? "\(count) zu bestätigen" : ""
            case .settings:
                return model.sidebar.cloudStatus.needsAttention ? "Sync braucht Aufmerksamkeit" : ""
            case .budget:
                return ""
            }
        }
    }

    private struct BadgeCount: View {
        let count: Int

        var body: some View {
            Text(verbatim: count > 99 ? "99+" : String(count))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ThemeColor.negativeContent)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(ThemeColor.negative))
                .accessibilityHidden(true)
        }
    }

    private struct AddTransactionButton: View {
        let register: RegisterViewModel
        let size: CGFloat
        let onAdd: (_ transfer: Bool) -> Void

        var body: some View {
            Group {
                if register.showsTransferButton {
                    Menu {
                        Button(RegisterViewModel.transferTitle, systemImage: "arrow.left.arrow.right") {
                            onAdd(true)
                        }
                    } label: {
                        plus
                    } primaryAction: {
                        onAdd(false)
                    }
                    .menuIndicator(.hidden)
                } else {
                    Button {
                        onAdd(false)
                    } label: {
                        plus
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThemeColor.text)
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(!register.canAddTransactions)
            .accessibilityLabel(RegisterViewModel.addTitle)
            .accessibilityShowsLargeContentViewer {
                Label(RegisterViewModel.addTitle, systemImage: "plus")
            }
        }

        private var plus: some View {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
    }

    @MainActor
    @Observable
    final class DockState {
        static let contentGap: CGFloat = 8

        private(set) var isMinimized = false
        var isHidden = false
        /// How far the dock reaches above the safe area, so scrolled content ends clear of it.
        var clearance: CGFloat = 0

        func expand() {
            if isMinimized { isMinimized = false }
        }

        func minimize() {
            if !isMinimized { isMinimized = true }
        }
    }

    extension EnvironmentValues {
        @Entry var dock: DockState?
    }

    extension View {
        /// The dock shrinks while the content scrolls down, which ends clear of it and fades under it.
        func scrollsUnderDock() -> some View {
            modifier(DockScrolling())
        }
    }

    /// VoiceOver keeps the dock whole, as a shrunk one hides the other tabs.
    private struct DockScrolling: ViewModifier {
        private static let threshold: CGFloat = 24

        @Environment(\.dock) private var dock
        @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverRunning
        @State private var turn: CGFloat = 0
        @State private var isScrollingDown = true

        func body(content: Content) -> some View {
            content
                .onScrollGeometryChange(for: CGFloat.self, of: Self.offset) { old, new in
                    follow(from: old, to: new)
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    if let dock, !dock.isHidden {
                        Color.clear.frame(height: dock.clearance).allowsHitTesting(false)
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        }

        private static func offset(_ geometry: ScrollGeometry) -> CGFloat {
            let insets = geometry.contentInsets
            let offset = geometry.contentOffset.y + insets.top
            let end = geometry.contentSize.height + insets.top + insets.bottom - geometry.containerSize.height
            return min(max(offset, 0), max(end, 0))
        }

        private func follow(from old: CGFloat, to new: CGFloat) {
            guard let dock, !isVoiceOverRunning, new != old else { return }
            guard new > 0 else {
                dock.expand()
                return
            }
            let isDown = new > old
            if isDown != isScrollingDown {
                isScrollingDown = isDown
                turn = old
            }
            if isDown && new - turn > Self.threshold {
                dock.minimize()
            } else if !isDown && turn - new > Self.threshold {
                dock.expand()
            }
        }
    }
#endif

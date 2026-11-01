import AbakusCore
import AppKit
import SwiftUI

public enum MainWindowMetrics {
    public static let defaultSize = CGSize(width: 1020, height: 700)
    public static let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    /// The 800×550 minimum covers the whole window, title bar included.
    @MainActor public static var minimumContentSize: CGSize {
        let frame = NSRect(origin: .zero, size: CGSize(width: 800, height: 550))
        return NSWindow.contentRect(forFrameRect: frame, styleMask: styleMask).size
    }
}

public struct MainWindowContent: View {
    let model: AppModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                model: model.sidebar, onAddAccount: model.accounts.addAccountClicked,
                onEditAccount: model.accounts.editAccountRequested
            )
            // A column width only takes effect on the column's root view.
            .modifier(SidebarWidth(isFullView: model.sidebar.isFullView))
        } detail: {
            MainPanel(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The narrow mode replaces hiding the sidebar.
        .onChange(of: columnVisibility) { columnVisibility = .all }
        .tint(ThemeColor.accent)
        .overlayPreferenceValue(SidebarRowAnchorKey.self) { anchors in
            AccountEditLayer(controller: model.accounts, anchors: anchors)
        }
        .overlayPreferenceValue(SidebarGroupAnchorKey.self) { anchors in
            if model.register.reconciliation.showsReconcileHelp {
                ReconcileHelpLayer(reconciliation: model.register.reconciliation, anchor: anchors[.budgetAccounts])
            }
        }
        .onChange(of: model.register.reconciliation.showsReconcileHelp) { _, shows in
            if shows { model.sidebar.reveal(.budget) }
        }
        .overlayPreferenceValue(BudgetPopupAnchorKey.self) { anchor in
            if model.navigation.selection == .budget {
                BudgetCalloutLayer(model: model.budget, anchor: anchor)
            }
        }
        .sheet(item: Binding(get: { model.sheet }, set: { _ in })) { sheet in
            AppSheetView(model: model, sheet: sheet)
        }
        .background { DialogHost(dialogs: model.presentedDialogs) }
        .task { await model.runDateTimer() }
    }
}

struct MainPanel: View {
    let model: AppModel

    var body: some View {
        if model.navigation.selection == .budget {
            BudgetView(model: model.budget)
        } else if model.showsRegister {
            RegisterView(model: model.register)
        } else {
            RegisterPlaceholder(title: model.selectionTitle)
        }
    }
}

struct AppSheetView: View {
    let model: AppModel
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .addCategory(let request): AddCategorySheet(request: request)
        case .payeeSettings(let payees): PayeeSettingsSheet(model: payees)
        case .renamePayee(let form):
            RenamePayeeSheet(
                form: form, onRename: model.register.renamePayeeConfirmed,
                onCancel: model.register.renamePayeeCancelled)
        case .statement(let form): StatementSheet(model: model.register, form: form)
        case .addAccount(let form): AddAccountSheet(controller: model.accounts, form: form)
        case .adjustBalance(let form): AdjustBalanceSheet(controller: model.accounts, form: form)
        }
    }
}

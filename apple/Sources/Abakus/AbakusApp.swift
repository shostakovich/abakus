import AbakusCore
import AbakusUI
import AppKit
import Network
import SwiftUI
import SystemConfiguration

@main
struct AbakusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    private let network = NWPathMonitor()

    init() {
        let location =
            BudgetDatabase.location(environment: ProcessInfo.processInfo.environment) ?? BudgetDatabase.defaultLocation
        let store: BudgetStore
        do {
            store = try BudgetStore.open(BudgetDatabase(url: location))
        } catch {
            Self.alert(error.localizedDescription, style: .critical)
            exit(1)
        }
        if let notice = store.openNotice { Self.alert(notice, style: .warning) }
        let sync = BudgetSync(
            store: store, tokens: KeychainTokenStore(account: location.path),
            deviceName: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac")
        sync?.start()
        network.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in sync?.syncNow() }
        }
        network.start(queue: .main)
        _model = State(initialValue: AppModel(store: store, sync: sync))
    }

    private static func alert(_ message: String, style: NSAlert.Style) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = "Abakus"
        alert.informativeText = message
        alert.runModal()
    }

    /// SwiftUI's default size covers the title bar; `MainWindowMetrics.defaultSize` is the content area below it.
    private static var defaultWindowSize: CGSize {
        let content = NSRect(origin: .zero, size: MainWindowMetrics.defaultSize)
        return NSWindow.frameRect(forContentRect: content, styleMask: MainWindowMetrics.styleMask).size
    }

    var body: some Scene {
        Window("Abakus", id: "main") {
            MainWindowContent(model: model)
                .frame(
                    minWidth: MainWindowMetrics.minimumContentSize.width,
                    minHeight: MainWindowMetrics.minimumContentSize.height
                )
                .background(CloseButtonQuits())
                .background(DocumentEdited(isEdited: model.store.hasUnsavedChanges))
                .onAppear { appDelegate.shouldTerminate = { [model] in model.commitBeforeQuit() } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.sync?.syncNow()
                }
        }
        .defaultSize(Self.defaultWindowSize)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(before: .toolbar) {
                Button("Zum Budget") { model.goToBudget() }
                    .keyboardShortcut("b")
                Button("Zu den Konten") { model.goToAccounts() }
                    .keyboardShortcut("t")
                Button("Empfänger verwalten …") { model.register.payeeSettingsShortcut() }
                    .keyboardShortcut("y")
                Divider()
            }
            CommandGroup(replacing: .sidebar) {
                Button(model.sidebar.toggleCommandTitle) { model.sidebar.toggleSidebar() }
            }
            RegisterCommands(model: model)
            CommandGroup(after: .pasteboard) {
                if model.showsAccountProperties {
                    Divider()
                    Button("Konto bearbeiten …") { model.accountPropertiesClicked() }
                }
            }
        }
        Settings {
            SettingsView(model: model.syncSettings)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var shouldTerminate: () -> Bool = { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Closing the only window quits, so the close button asks the quit gate while the window is still there.
private struct CloseButtonQuits: NSViewRepresentable {
    final class RoutingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let button = window?.standardWindowButton(.closeButton) else { return }
            button.target = NSApp
            button.action = #selector(NSApplication.terminate(_:))
        }
    }

    func makeNSView(context: Context) -> NSView { RoutingView() }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Unsaved changes show as the dot in the close button; the toolbar's title belongs to the screen.
private struct DocumentEdited: NSViewRepresentable {
    let isEdited: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.isDocumentEdited = isEdited
    }
}

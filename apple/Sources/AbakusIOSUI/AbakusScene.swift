#if os(iOS)
    import AbakusCore
    import AbakusUI
    import Network
    import SwiftUI
    import UIKit

    /// The app's one window; the Xcode project's app only hosts it.
    public struct AbakusScene: Scene {
        public init() {}

        public var body: some Scene {
            WindowGroup {
                switch AppLaunch.shared.outcome {
                case .opened(let model, let navigation): RootView(model: model, navigation: navigation)
                case .failed(let message):
                    ContentUnavailableView(
                        "Abakus kann das Budget nicht öffnen", systemImage: "exclamationmark.triangle",
                        description: Text(message))
                }
            }
            .commands {
                if case .opened(let model, let navigation) = AppLaunch.shared.outcome {
                    let waits = navigation.showsSheet
                    CommandGroup(replacing: .appSettings) {
                        Button("Einstellungen …", action: navigation.goToSettings).keyboardShortcut(",").disabled(waits)
                    }
                    CommandGroup(before: .toolbar) {
                        Button("Zum Budget", action: navigation.goToBudget).keyboardShortcut("b").disabled(waits)
                        Button("Zu den Konten", action: navigation.goToAccounts).keyboardShortcut("t").disabled(waits)
                        Button(PayeeSettingsModel.title + " …", action: model.register.payeeSettingsShortcut)
                            .keyboardShortcut("y")
                            .disabled(model.showsScreenSheet)
                    }
                    RegisterCommands(model: model, addsEverywhere: true, addingWaits: waits)
                    CommandGroup(after: .pasteboard) {
                        if model.showsAccountProperties {
                            Button("Konto bearbeiten …", action: model.accountPropertiesClicked)
                                .disabled(model.showsScreenSheet)
                        }
                    }
                }
            }
        }
    }

    /// Opened once per process, as the budget's lock lets only one store open it.
    @MainActor
    final class AppLaunch {
        enum Outcome {
            case opened(AppModel, TouchNavigation)
            case failed(String)
        }

        static let shared = AppLaunch()

        let outcome: Outcome
        private let network = NWPathMonitor()

        private init() {
            UISearchTextField.appearance().tokenBackgroundColor = ThemeColor.searchTokenFill
            let location =
                BudgetDatabase.location(environment: ProcessInfo.processInfo.environment)
                ?? BudgetDatabase.defaultLocation
            let store: BudgetStore
            do {
                store = try BudgetStore.open(BudgetDatabase(url: location))
            } catch {
                outcome = .failed(error.localizedDescription)
                return
            }
            let device: DeviceKind = UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
            let account = KeychainTokenStore.account(
                forDatabaseAt: location, inContainer: URL(fileURLWithPath: NSHomeDirectory()))
            let sync = BudgetSync(store: store, tokens: KeychainTokenStore(account: account), deviceName: device.name)
            network.pathUpdateHandler = { path in
                guard path.status == .satisfied else { return }
                Task { @MainActor in sync?.syncNow() }
            }
            network.start(queue: .main)
            let model = AppModel(store: store, sync: sync, device: device)
            if let notice = store.openNotice { model.dialogs.show(.message("Abakus", notice)) }
            outcome = .opened(model, TouchNavigation(app: model))
        }
    }
#endif

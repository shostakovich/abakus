import AbakusCore
import SwiftUI

public struct SettingsView: View {
    let model: SyncSettingsModel?

    public init(model: SyncSettingsModel?) {
        self.model = model
    }

    public var body: some View {
        TabView {
            Tab("Sync", systemImage: "arrow.triangle.2.circlepath.icloud") {
                if let model {
                    SyncSettingsView(model: model)
                } else {
                    Text("Dieses Budget lässt sich nicht synchronisieren.").padding()
                }
            }
        }
        .frame(width: 480)
    }
}

struct SyncSettingsView: View {
    @Bindable var model: SyncSettingsModel

    var body: some View {
        Form {
            Section {
                TextField("Serveradresse", text: $model.serverAddress, prompt: Text("https://abakus.example.org"))
                    .disabled(!model.canEditAddress)
                    .onSubmit(signIn)
                if let error = model.addressError {
                    Text(error).foregroundStyle(ThemeColor.negative).font(.callout)
                }
            }
            Section {
                Label {
                    Text(model.statusText).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: cloud.symbolName)
                }
                if let error = model.sync.signInError {
                    Text(error).foregroundStyle(ThemeColor.negative).font(.callout)
                }
                HStack {
                    Spacer()
                    if model.showsSignOut {
                        Button("Abmelden …") { Task { await model.signOutClicked() } }
                    }
                    if model.showsSignIn {
                        Button("Anmelden", action: signIn)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!model.canSignIn)
                    }
                    if model.sync.isSigningIn { ProgressView().controlSize(.small) }
                }
            }
        }
        .formStyle(.grouped)
        .alert(
            "Von Abakus abmelden?",
            isPresented: Binding(
                get: { model.signOutWarning != nil }, set: { if !$0 { model.cancelSignOut() } })
        ) {
            Button("Abmelden", role: .destructive) { Task { await model.confirmSignOut() } }
            Button("Abbrechen", role: .cancel) { model.cancelSignOut() }
        } message: {
            Text(model.signOutWarningText + " Dann löscht Abakus das Budget auf diesem Mac und zeigt das Demo-Budget.")
        }
    }

    private var cloud: CloudSyncStatus {
        CloudSyncStatus(model.sync.status, pendingChanges: model.sync.pendingChanges, lastSync: model.sync.lastSync)
    }

    private func signIn() {
        Task { await model.signInClicked() }
    }
}

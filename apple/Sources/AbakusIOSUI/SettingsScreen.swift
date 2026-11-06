#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct SettingsScreen: View {
        static var version: String {
            let info = Bundle.main.infoDictionary ?? [:]
            let version = info["CFBundleShortVersionString"] as? String ?? "–"
            return (info["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
        }

        let model: SyncSettingsModel?

        var body: some View {
            Form {
                if let model {
                    SyncSections(model: model)
                } else {
                    Section {
                        Label("Dieses Budget lässt sich nicht synchronisieren.", systemImage: "icloud.slash")
                    }
                }
                Section("Budget") {
                    NavigationLink(value: PayeeRoute.payees) {
                        Label("Empfänger", systemImage: "person.2")
                    }
                }
                Section("Info") {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .readableListWidth()
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .scrollsUnderDock()
        }
    }

    private struct SyncSections: View {
        @Bindable var model: SyncSettingsModel

        var body: some View {
            Section {
                LabeledContent("Server") {
                    TextField("Server", text: $model.serverAddress, prompt: Text("https://abakus.example.org"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .disabled(!model.canEditAddress)
                        .onSubmit(signIn)
                }
                if let error = model.addressError {
                    Text(error).foregroundStyle(ThemeColor.negative).font(.callout)
                }
            } footer: {
                Text(
                    "Abakus synchronisiert dein Budget über deinen Abakus-Server mit dem Web und deinen anderen Geräten."
                )
            }
            if model.showsSignIn {
                Section {
                    Button(action: signIn) {
                        ZStack {
                            Text("Anmelden").opacity(model.sync.isSigningIn ? 0 : 1)
                            if model.sync.isSigningIn { ProgressView().tint(.white) }
                        }
                    }
                    .buttonStyle(ProminentCapsuleButtonStyle())
                    .disabled(!model.canSignIn)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            Section("Status") {
                Label {
                    Text(model.statusText)
                } icon: {
                    Image(systemName: model.cloudStatus.symbolName)
                        .foregroundStyle(model.cloudStatus.needsAttention ? ThemeColor.negative : ThemeColor.accent)
                }
                if let error = model.sync.signInError {
                    Text(error).foregroundStyle(ThemeColor.negative).font(.callout)
                }
                if model.showsSignOut {
                    Button("Abmelden", role: .destructive) { Task { await model.signOutClicked() } }
                }
            }
            .alert(
                "Von Abakus abmelden?",
                isPresented: Binding(
                    get: { model.signOutWarning != nil }, set: { if !$0 { model.cancelSignOut() } })
            ) {
                Button("Abmelden", role: .destructive) { Task { await model.confirmSignOut() } }
                Button("Abbrechen", role: .cancel) { model.cancelSignOut() }
            } message: {
                Text(model.signOutWarningText)
            }
        }

        private func signIn() {
            Task { await model.signInClicked() }
        }
    }

    /// Disabled, the fill fades and the label stays white, so it reads on the faded fill in both themes.
    private struct ProminentCapsuleButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(isEnabled ? ThemeColor.selectedText : .white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(ThemeColor.accent).opacity(isEnabled ? 1 : 0.4))
                .opacity(configuration.isPressed ? 0.75 : 1)
                .contentShape(Capsule())
        }
    }
#endif

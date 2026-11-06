#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    /// The app without a sign-in: no tabs and no budget, only the way to the server's.
    struct SignInScreen: View {
        @Bindable var model: SyncSettingsModel

        var body: some View {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Text(SignInText.title).font(.largeTitle.weight(.bold))
                        Text(SignInText.message)
                            .foregroundStyle(ThemeColor.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .listRowBackground(Color.clear)
                }
                Section {
                    LabeledContent("Server") {
                        TextField("Server", text: $model.serverAddress, prompt: Text(SignInText.addressPrompt))
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .disabled(!model.canEditAddress)
                            .onSubmit(signIn)
                    }
                    if let error = model.addressError ?? model.sync.signInError {
                        Text(error).foregroundStyle(ThemeColor.negative).font(.callout)
                    }
                }
                Section {
                    Button(action: signIn) {
                        ZStack {
                            Text(SignInText.signIn).opacity(model.sync.isSigningIn ? 0 : 1)
                            if model.sync.isSigningIn { ProgressView().tint(.white) }
                        }
                    }
                    .buttonStyle(ProminentCapsuleButtonStyle())
                    .disabled(!model.canSignIn)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .readableListWidth()
            .tint(ThemeColor.accent)
        }

        private func signIn() {
            Task { await model.signInClicked() }
        }
    }
#endif

import AbakusCore
import AbakusUI
import SwiftUI

/// The window without a sign-in: no sidebar and no budget, only the way to the server's.
struct SignInView: View {
    @Bindable var model: SyncSettingsModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(SignInText.title).font(.largeTitle.weight(.semibold))
                Text(SignInText.message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Form {
                TextField("Server", text: $model.serverAddress, prompt: Text(SignInText.addressPrompt))
                    .disabled(!model.canEditAddress)
                    .onSubmit(signIn)
                if let error = model.addressError ?? model.sync.signInError {
                    Text(error).foregroundStyle(ThemeColor.negative).font(.callout)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: model.addressError ?? model.sync.signInError == nil ? 70 : 110)
            HStack(spacing: 8) {
                if model.sync.isSigningIn { ProgressView().controlSize(.small) }
                Button(SignInText.signIn, action: signIn)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSignIn)
            }
        }
        .frame(width: 400)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeColor.windowBackground)
        .tint(ThemeColor.accent)
        .navigationTitle("Abakus")
    }

    private func signIn() {
        Task { await model.signInClicked() }
    }
}

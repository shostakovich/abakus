import AbakusCore
import AppKit
import AuthenticationServices

@MainActor
public enum WebSignIn {
    public static func authorize(_ url: URL) async throws -> URL {
        let anchor = PresentationAnchor()
        defer { withExtendedLifetime(anchor) {} }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callback: .customScheme(AbakusServer.callbackScheme)
            ) { @Sendable callback, error in
                // AuthenticationServices calls back on a background queue.
                continuation.resume(with: result(callback, error))
            }
            session.presentationContextProvider = anchor
            if !session.start() {
                continuation.resume(throwing: SignInError.refused("Die Anmeldung ließ sich nicht öffnen."))
            }
            anchor.session = session
        }
    }

    nonisolated private static func result(_ callback: URL?, _ error: Error?) -> Result<URL, Error> {
        if let callback { return .success(callback) }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            return .failure(SignInError.cancelled)
        }
        return .failure(SignInError.refused(error?.localizedDescription ?? "Die Anmeldung schlug fehl."))
    }

    private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        var session: ASWebAuthenticationSession?

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
        }
    }
}

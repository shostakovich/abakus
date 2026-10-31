import Foundation
import Testing

@testable import AbakusCore

@Suite struct SignInRequestTests {
    let request = SignInRequest(verifier: String(repeating: "v", count: 43), state: "STATE")

    private func callback(_ query: String) -> URL {
        URL(string: "local.abakus:/oauth/callback?\(query)")!
    }

    @Test func theCallbackGivesTheCode() throws {
        #expect(try request.code(from: callback("code=CODE&state=STATE&iss=https://abakus.test")) == "CODE")
    }

    @Test func aCallbackForAnotherRequestIsRefused() {
        #expect(throws: SignInError.refused("Die Anmeldung passt nicht zu dieser Anfrage.")) {
            try request.code(from: callback("code=CODE&state=OTHER"))
        }
        #expect(throws: SignInError.refused("Die Anmeldung passt nicht zu dieser Anfrage.")) {
            try request.code(from: callback("code=CODE"))
        }
    }

    @Test func aRefusalByTheOwnerCancelsTheSignIn() {
        #expect(throws: SignInError.cancelled) {
            try request.code(from: callback("error=access_denied&state=STATE"))
        }
    }

    @Test func anotherErrorIsShown() {
        #expect(throws: SignInError.refused("Abakus hat die Anmeldung abgelehnt (invalid_request).")) {
            try request.code(from: callback("error=invalid_request&state=STATE"))
        }
    }

    @Test func aCallbackWithoutACodeIsRefused() {
        #expect(throws: SignInError.refused("Abakus hat keinen Anmeldecode geschickt.")) {
            try request.code(from: callback("state=STATE"))
        }
        #expect(throws: SignInError.refused("Abakus hat keinen Anmeldecode geschickt.")) {
            try request.code(from: callback("code=&state=STATE"))
        }
    }
}

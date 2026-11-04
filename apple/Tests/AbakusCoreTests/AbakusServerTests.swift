import AbakusCore
import Foundation
import Testing

private struct AnsweringTransport: HTTPTransport {
    var status = 200
    let contentType: String
    let body: String

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": contentType])!
        return (Data(body.utf8), response)
    }
}

struct AbakusServerTests {
    private func exchange(status: Int = 200, contentType: String, body: String) async throws {
        let server = AbakusServer(
            url: URL(string: "https://abakus.test")!,
            transport: AnsweringTransport(status: status, contentType: contentType, body: body))
        _ = try await server.exchange(code: "code", verifier: String(repeating: "v", count: 43), now: Date())
    }

    @Test func aWebPageInsteadOfDataPointsAtASignInServiceInFront() async throws {
        await #expect(
            throws: SyncError.refused(
                "Abakus antwortete mit einer Webseite statt mit Daten. Vermutlich lässt ein Anmeldedienst vor dem "
                    + "Server die App nicht durch.")
        ) {
            try await exchange(contentType: "text/html; charset=utf-8", body: "<!doctype html><title>Login</title>")
        }
    }

    @Test func aRefusingWebPageAlsoPointsAtASignInServiceInFront() async throws {
        await #expect(
            throws: SyncError.refused(
                "Abakus antwortete mit einer Webseite statt mit Daten. Vermutlich lässt ein Anmeldedienst vor dem "
                    + "Server die App nicht durch.")
        ) {
            try await exchange(status: 403, contentType: "text/html", body: "<!doctype html><title>Forbidden</title>")
        }
        await #expect(throws: SyncError.invalidToken) {
            try await exchange(status: 401, contentType: "text/html", body: "<!doctype html><title>Login</title>")
        }
    }

    @Test func otherUnreadableDataSaysSo() async throws {
        await #expect(throws: SyncError.refused("Die Antwort von Abakus ließ sich nicht lesen.")) {
            try await exchange(contentType: "application/json", body: "{\"unexpected\": true}")
        }
    }
}

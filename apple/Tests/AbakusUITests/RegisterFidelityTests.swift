import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterFidelityTests {
    @Test func summarySearchesHaveNoTrailingComma() {
        let model = RegisterFixture().model()
        model.summaryClicked(.cleared)
        #expect(model.search.text == "Ist: Gebucht oder abgeglichen")
        model.notifiers.clicked(.warning)
        #expect(model.search.text == "Ist: Nicht kategorisiert, ")
    }
}

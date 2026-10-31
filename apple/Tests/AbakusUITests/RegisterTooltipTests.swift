import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterTooltipTests {
    @Test func clearedCellsExplainTheirStatus() {
        var fixture = RegisterFixture()
        let cleared = fixture.add(fixture.giro, -1, cleared: .cleared)
        let reconciled = fixture.add(fixture.giro, -2, cleared: .reconciled)
        let rows = fixture.model().rows
        #expect(
            rows.first { $0.id == cleared }?.clearedTooltip
                == "Gebucht: Die Bank kennt diese Buchung. Klicken, um sie als vorgemerkt zu markieren.")
        #expect(
            rows.first { $0.id == reconciled }?.clearedTooltip
                == "Abgeglichen: Die Bank kennt diese Buchung, und sie ist mit dem Banksaldo abgeglichen.")
    }

    @Test func theReconcileTooltipOnlyExplainsAllAccounts() {
        let fixture = RegisterFixture()
        let giro = fixture.model()
        let allAccounts = fixture.model(selection: .allAccounts)
        #expect(giro.reconciliation.reconcileTooltip == nil)
        #expect(
            allAccounts.reconciliation.reconcileTooltip == "Wähle in der Seitenleiste ein Konto zum Abgleichen.")
    }
}

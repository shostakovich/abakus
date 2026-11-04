import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterPickingTests {
    @MainActor
    private struct Imports {
        let model: RegisterViewModel
        let store: SpyBudgetStore
        let ids: [String]

        init(count: Int = 3) {
            var fixture = RegisterFixture()
            ids = (1...count).map { index in
                fixture.add(
                    fixture.giro, Decimal(-index), category: fixture.groceries, approved: false, source: .bank)
            }
            (model, store) = fixture.spied(appliesCommands: true)
        }

        func choose(_ title: String, showsColumns: Bool = false) {
            guard case .action(let action) = model.touchViewMenu(showsColumns: showsColumns).item(titled: title)?.kind
            else {
                Issue.record("Ansicht has no item \(title)")
                return
            }
            model.performMenuAction(action)
        }
    }

    @Test func approvingWhatAuswählenSelectedApprovesExactlyThose() {
        let imports = Imports()
        let (first, second, third) = (imports.ids[0], imports.ids[1], imports.ids[2])
        imports.choose("Auswählen")
        #expect(imports.model.isPicking)
        imports.model.setSelection([first, third])
        imports.model.performMenuAction(.approve)
        guard case .approveTransactions(let approved) = imports.store.commands.last else {
            Issue.record("Nothing approved")
            return
        }
        #expect(Set(approved) == [first, third])
        #expect(imports.store.budget.transaction(withId: second)?.needsApproval == true)
        #expect(imports.store.budget.transaction(withId: first)?.needsApproval == false)
    }

    @Test func endingAuswählenClearsTheSelection() {
        let imports = Imports()
        imports.choose("Auswählen")
        imports.model.setSelection([imports.ids[0]])
        imports.choose("Auswählen beenden")
        #expect(!imports.model.isPicking)
        #expect(imports.model.selection.isEmpty)
    }

    @Test func alleAuswählenTakesTheWholeViewAndGivesItBack() {
        let imports = Imports()
        imports.choose("Alle auswählen")
        #expect(imports.model.selection.count == imports.model.transactionIds.count)
        imports.choose("Auswahl aufheben")
        #expect(imports.model.selection.isEmpty)
    }

    @Test func anotherAccountEndsAuswählen() {
        let imports = Imports()
        imports.choose("Auswählen")
        imports.model.navigation.selection = .allAccounts
        #expect(!imports.model.isPicking)
    }

    @Test func aContextMenuActsOnTheRowsItWasOpenedFor() {
        let imports = Imports()
        let (first, second) = (imports.ids[0], imports.ids[1])
        let menu = imports.model.transactionActionsMenu(for: [second])
        #expect(menu.item(titled: "Bestätigen")?.isEnabled == true)
        imports.model.setSelection([first])
        imports.model.performMenuAction(.approve, on: [second])
        #expect(imports.store.commands.last == .approveTransactions([second]))
        #expect(imports.model.selectedTransactionIds == [second])
    }

    @Test func theTableAddsTheMemoAndBalanceColumnsButNotTheStatusToAnsicht() {
        let imports = Imports()
        let menu = imports.model.touchViewMenu(showsColumns: true)
        #expect(menu.item(titled: "Memo") != nil)
        #expect(menu.item(titled: "Laufender Saldo") != nil)
        #expect(menu.item(titled: "Status") == nil)
        #expect(imports.model.touchViewMenu(showsColumns: false).item(titled: "Memo") == nil)
    }

    @Test func ansichtNamesEveryTopLevelItemWithASymbolAndShortLabels() {
        let imports = Imports()
        let items = imports.model.touchViewMenu(showsColumns: true).filter { $0.kind != .separator }
        #expect(items.allSatisfy { $0.systemImage != nil })
        #expect(items.map(\.title) == ["Zeitraum", "Abgeglichene", "Auswählen", "Alle auswählen", "Spalten"])
        #expect(items.map(\.subtitle) == ["Alle Daten", "Gezeigt", nil, nil, nil])
        #expect(items.allSatisfy { !$0.isChecked })
    }

    @Test func tappingTheStatusApprovesAWaitingRowElseSwitchesItsCleared() {
        var fixture = RegisterFixture()
        let waiting = fixture.add(fixture.giro, -1, approved: false, source: .bank)
        let uncleared = fixture.add(fixture.giro, -2)
        let cleared = fixture.add(fixture.giro, -3, cleared: .cleared)
        let reconciled = fixture.add(fixture.giro, -4, cleared: .reconciled)
        let (model, _) = fixture.spied()
        func action(_ id: String) -> RegisterMenuAction? {
            model.statusAction(for: model.rows.first { $0.id == id }!)
        }
        #expect(action(waiting) == .approve)
        #expect(action(uncleared) == .markCleared)
        #expect(action(cleared) == .markUncleared)
        #expect(action(reconciled) == nil)
    }

    @Test func thePickingBarOffersApprovingWhileARowWaitsElseTheClearedSwitch() {
        var fixture = RegisterFixture()
        let waiting = fixture.add(fixture.giro, -1, approved: false, source: .bank)
        let uncleared = fixture.add(fixture.giro, -2)
        let cleared = fixture.add(fixture.giro, -3, cleared: .cleared)
        let reconciled = fixture.add(fixture.giro, -4, cleared: .reconciled)
        let (model, _) = fixture.spied()
        func status(_ ids: Set<String>) -> (RegisterMenuAction, Bool) {
            model.setSelection(ids)
            let actions = model.pickingActions
            return (actions.status, actions.isStatusEnabled)
        }
        #expect(status([waiting, cleared]) == (.approve, true))
        #expect(status([uncleared, cleared]) == (.markCleared, true))
        #expect(status([cleared]) == (.markUncleared, true))
        #expect(status([reconciled]) == (.markCleared, false))
        #expect(status([]) == (.markCleared, false))
    }

    @Test func thePickingBarCategorizesAndDeletesOnlyWhatIsPickedInABudgetAccount() {
        var fixture = RegisterFixture()
        let giro = fixture.add(fixture.giro, -1)
        let depot = fixture.add(fixture.depot, -1)
        let (model, _) = fixture.spied()
        #expect(model.pickingActions.categories.isEmpty)
        #expect(!model.pickingActions.canDelete)
        model.setSelection([giro])
        #expect(!model.pickingActions.categories.isEmpty)
        #expect(model.pickingActions.canDelete)
        #expect(model.pickingActions.deleteQuestion == "Buchung löschen?")
        let (tracking, _) = fixture.spied(selection: .account(fixture.depot))
        tracking.setSelection([depot])
        #expect(tracking.pickingActions.categories.isEmpty)
        #expect(tracking.pickingActions.canDelete)
    }
}

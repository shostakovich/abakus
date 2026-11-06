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

    @Test func thePickingBarDeletesWhatIsPickedAtOnceAndOffersUndo() {
        let imports = Imports()
        let (first, second, third) = (imports.ids[0], imports.ids[1], imports.ids[2])
        imports.choose("Auswählen")
        imports.model.setSelection([first, third])
        imports.model.performMenuAction(.delete, on: imports.model.pickingActions.ids)
        #expect(!imports.model.dialogs.isPresenting)
        #expect(imports.store.budget.transaction(withId: first) == nil)
        #expect(imports.store.budget.transaction(withId: second) != nil)
        #expect(imports.model.notifiers.undoSlot?.message == "2 Buchungen gelöscht")
    }

    @Test func endingAuswählenClearsTheSelection() {
        let imports = Imports()
        imports.choose("Auswählen")
        imports.model.setSelection([imports.ids[0]])
        imports.choose("Auswählen beenden")
        #expect(!imports.model.isPicking)
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
        #expect(!imports.model.transactionActionsMenu(for: [second]).contains { $0.title.hasSuffix("…") })
        imports.model.setSelection([first])
        imports.model.performMenuAction(.categorize(categoryId: nil), on: [second])
        #expect(imports.store.commands.last == .categorizeTransactions([second], categoryId: nil))
        #expect(imports.model.selectedTransactionIds == [second])
    }

    @Test func theLongPressMenuDeletesInRed() {
        let imports = Imports()
        imports.model.isTouch = true
        let delete = imports.model.transactionActionsMenu(for: [imports.ids[0]]).item(titled: "Löschen")
        #expect(delete?.isDestructive == true)
    }

    @Test func theTableAddsTheMemoButNotTheStatusToAnsicht() {
        let imports = Imports()
        let menu = imports.model.touchViewMenu(showsColumns: true)
        #expect(menu.item(titled: "Memo ausblenden") != nil)
        #expect(menu.item(titled: "Status") == nil)
        #expect(imports.model.touchViewMenu(showsColumns: false).item(titled: "Memo ausblenden") == nil)
    }

    @Test func ansichtChecksTheViewAndKeepsAlleForPicking() {
        let imports = Imports()
        let items = imports.model.touchViewMenu(showsColumns: true).filter { $0.kind != .separator }
        #expect(items.allSatisfy { $0.systemImage != nil })
        #expect(
            items.map(\.title) == [
                "Alle Buchungen", "Zu bestätigen", "Vorgemerkt", "Ohne Kategorie", "Geplante Buchungen", "Auswählen",
                "Memo ausblenden", "Konto bearbeiten",
            ])
        #expect(items.filter(\.isChecked).map(\.title) == ["Alle Buchungen"])
    }

    @Test func tappingTheStatusApprovesAWaitingRowElseSwitchesItsCleared() {
        var fixture = RegisterFixture()
        let waiting = fixture.add(fixture.giro, -1, approved: false, source: .bank)
        let uncleared = fixture.add(fixture.giro, -2)
        let cleared = fixture.add(fixture.giro, -3, cleared: .cleared)
        let reconciled = fixture.add(fixture.giro, -4, cleared: .reconciled)
        let (model, store) = fixture.spied()
        func row(_ id: String) -> RegisterRow { model.rows.first { $0.id == id }! }
        #expect(model.statusAction(for: row(waiting)) == .approve)
        #expect(model.statusAction(for: row(uncleared)) == .markCleared)
        #expect(model.statusAction(for: row(cleared)) == .markUncleared)
        #expect(model.statusAction(for: row(reconciled)) == .unlock)
        model.statusTapped(row(waiting))
        model.statusTapped(row(uncleared))
        #expect(store.commands == [.approveTransactions([waiting]), .toggleCleared([uncleared])])
        model.statusTapped(row(reconciled))
        #expect(model.dialogs.presented.last?.dialog.instruction == "Diese Buchung ist abgeglichen. Entsperren?")
        model.dialogs.presented.last?.answer(UnlockChoice.unlock)
        #expect(store.commands.last == .setCleared([reconciled], .cleared))
    }

    @Test func thePickingBarHasNoStatusButton() {
        var fixture = RegisterFixture()
        let waiting = fixture.add(fixture.giro, -1, approved: false, source: .bank)
        let (model, _) = fixture.spied()
        model.setSelection([waiting])
        let actions = model.pickingActions
        #expect(actions.menu.item(titled: "Bestätigen") == nil)
        #expect(actions.menu.item(titled: "Als gebucht markieren") == nil)
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
        let (tracking, _) = fixture.spied(selection: .account(fixture.depot))
        tracking.setSelection([depot])
        #expect(tracking.pickingActions.categories.isEmpty)
        #expect(tracking.pickingActions.canDelete)
    }
}

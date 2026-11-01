import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct EditorOvertakenTests {
    private func editingMemo(_ fixture: inout RegisterFixture) -> (RegisterViewModel, String) {
        let id = fixture.add(fixture.giro, -10, category: fixture.groceries)
        let model = fixture.model()
        model.beginEditing(id, column: .memo)
        model.editor?.type("changed")
        return (model, id)
    }

    @Test func savingAnEditKeepsWhatAnotherWriterChangedMeanwhile() throws {
        var fixture = RegisterFixture()
        let (model, id) = editingMemo(&fixture)
        let fuel = fixture.category("Everyday Expenses", "Fuel")
        var remote = try #require(model.store.budget.transaction(withId: id))
        remote.categoryId = fuel
        remote.amount = -12
        try model.store.perform(.updateTransaction(remote, payeeName: "Tankstelle"))

        model.editor?.activate(.save)

        let saved = try #require(model.store.budget.transaction(withId: id))
        #expect(saved.memo == "changed")
        #expect(saved.categoryId == fuel)
        #expect(saved.amount == -12)
        #expect(model.store.budget.payeeName(of: saved) == "Tankstelle")
    }

    @Test func savingAnEditWritesTheFieldsTheOwnerChanged() throws {
        var fixture = RegisterFixture()
        let (model, id) = editingMemo(&fixture)
        var remote = try #require(model.store.budget.transaction(withId: id))
        remote.memo = "remote"
        try model.store.perform(.updateTransaction(remote))

        model.editor?.activate(.save)

        #expect(model.store.budget.transaction(withId: id)?.memo == "changed")
    }

    @Test func theViewMenuGlowsWhileTheEditHasChanges() throws {
        var fixture = RegisterFixture()
        let (model, _) = editingMemo(&fixture)
        model.viewMenuChosen(.toggleColumn(.runningBalance))
        #expect(!model.visibleColumns.contains(.runningBalance))
        #expect(model.editor?.glowCount == 1)
    }

    @Test func theViewMenuEndsAnUnchangedEditFirst() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10, category: fixture.groceries)
        let model = fixture.model()
        model.beginEditing(id)
        model.viewMenuChosen(.toggleColumn(.runningBalance))
        #expect(model.editor == nil)
        #expect(model.visibleColumns.contains(.runningBalance))
    }

    @Test func aSearchThatHidesTheEditedRowEndsTheEdit() {
        var fixture = RegisterFixture()
        let (model, _) = editingMemo(&fixture)
        model.search.boxChanged("payee:nobody,")
        #expect(model.transactionIds.isEmpty)
        #expect(model.editor == nil)
    }

    @Test func headerClicksGlowWhileTheEditHasChanges() {
        var fixture = RegisterFixture()
        let (model, _) = editingMemo(&fixture)
        model.grid.headerClicked(.runningBalance)
        model.grid.headerClicked(.payee)
        #expect(model.selection.count == 1)
        #expect(model.sortOrder == .default)
        #expect(model.editor?.glowCount == 2)
    }

    @Test func splitArrowGlowsWhileTheEditHasChanges() {
        var fixture = RegisterFixture()
        let split = fixture.add(
            fixture.giro, -10, category: EntityID.splitCategory,
            subtransactions: [
                Subtransaction(transactionId: "", amount: -4, categoryId: fixture.groceries),
                Subtransaction(transactionId: "", amount: -6, categoryId: fixture.groceries),
            ])
        let (model, _) = editingMemo(&fixture)
        model.toggleSplit(split)
        #expect(!model.expandedSplits.contains(split))
        #expect(model.editor?.glowCount == 1)
    }

    @Test func hidingTheSchedulerGlowsAtAChangedEditAndEndsAnUnchangedOne() throws {
        var fixture = RegisterFixture()
        fixture.addSchedule("S1", category: fixture.groceries)
        let model = fixture.model()
        model.scheduledToggleClicked()
        model.scheduler.beginEditing("S1", column: .memo)
        let editor = try #require(model.scheduler.editor)
        editor.type("changed")
        model.scheduledToggleClicked()
        #expect(model.isSchedulerVisible)
        #expect(editor.glowCount == 1)
        #expect(model.scheduler.editor === editor)
        editor.activate(.cancel)
        model.scheduler.beginEditing("S1", column: .memo)
        model.scheduledToggleClicked()
        #expect(!model.isSchedulerVisible)
        #expect(model.scheduler.editor == nil)
    }

    @Test func swallowedSchedulerRightClickOpensNoMenu() throws {
        var fixture = RegisterFixture()
        fixture.addSchedule("S1", category: fixture.groceries)
        fixture.addSchedule("S2", category: fixture.groceries)
        let model = fixture.model()
        model.scheduler.beginEditing("S1", column: .memo)
        model.scheduler.editor?.type("changed")
        let other = try #require(model.scheduler.rows.first { $0.id == "S2" })
        #expect(!model.scheduler.contextClicked(other))
        #expect(model.scheduler.selectedIds == ["S1"])
    }

    @Test func abgleichenGlowsAtAChangedEditInEitherGrid() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10, category: fixture.groceries)
        fixture.addSchedule("S1", category: fixture.groceries)
        let model = fixture.model()
        model.beginEditing(id, column: .memo)
        let editor = try #require(model.editor)
        editor.type("changed")
        model.reconciliation.reconcileClicked()
        #expect(model.reconciliation.statementForm == nil)
        #expect(editor.glowCount == 1)
        editor.activate(.cancel)
        model.scheduler.beginEditing("S1", column: .memo)
        let scheduled = try #require(model.scheduler.editor)
        scheduled.type("changed")
        model.reconciliation.reconcileClicked()
        #expect(model.reconciliation.statementForm == nil)
        #expect(scheduled.glowCount == 1)
    }

    @Test func finishingAReconciliationEndsTheEdit() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10, category: fixture.groceries, cleared: .cleared)
        let model = fixture.model()
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "1,101.00"
        model.reconciliation.begin(form)
        model.beginEditing(id)
        model.reconciliation.finishReconciliationClicked()
        #expect(!model.isReconciling)
        #expect(model.editor == nil)
    }

    @Test func aNewDayThatEntersTheEditedScheduleEndsTheEdit() {
        var fixture = RegisterFixture()
        let tomorrow = DateWithoutTime.today().addingDays(1)
        fixture.addSchedule("S1", on: tomorrow.description, category: fixture.groceries)
        let app = AppModel(store: BudgetStore(budget: fixture.budget), selection: .account(fixture.giro), defaults: nil)
        app.register.scheduler.beginEditing("S1", column: .memo)
        app.register.scheduler.editor?.type("changed")
        app.dateChecked(today: tomorrow)
        #expect(app.register.scheduler.editor == nil)
    }

}

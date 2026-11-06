import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct SchedulerTests {
    private func fixture(repeats: Repeat = .monthly, on date: String = "2014-06-02")
        -> RegisterFixture
    {
        var fixture = RegisterFixture()
        fixture.addSchedule(
            "S1", on: date, payee: "Farm", category: fixture.groceries, memo: "Box", repeats: repeats)
        return fixture
    }

    @Test func columnsFollowTheScheduleGrid() {
        let fixture = fixture()
        let giro = fixture.spied().model
        #expect(giro.scheduler.visibleColumns == [.date, .repeats, .payee, .category, .memo, .amount])
        let allAccounts = fixture.spied(selection: .allAccounts).model
        #expect(allAccounts.scheduler.visibleColumns.first == .account)
        let depot = fixture.spied(selection: .account(fixture.depot)).model
        #expect(!depot.scheduler.visibleColumns.contains(.category))
    }

    @Test func rowsShowTheNextDateAndTheRepeat() throws {
        let (model, _) = fixture().spied()
        let row = try #require(model.scheduler.rows.first)
        #expect(row.date == "02/06/14")
        #expect(row.repeatLabel == "Monatlich")
        #expect(row.payee == "Farm")
        #expect(row.category == "Groceries")
        #expect(row.amountText == "−25.00")
        #expect(model.scheduler.scheduledTransactions.count == 1)
    }

    @Test func splitLinesShowTheirCategoryInAnOffBudgetAccount() throws {
        var fixture = RegisterFixture()
        fixture.addSplitSchedule(account: fixture.depot)
        let (model, _) = fixture.spied(selection: .allAccounts)
        model.scheduler.grid.toggleSplit("S1")
        let rows = model.scheduler.rows
        #expect(rows.map(\.category) == ["", "Groceries", "Groceries"])
    }

    @Test func somethingPlannedShowsCollapsedWithItsCount() {
        var fixture = fixture()
        fixture.addSchedule("S2", account: fixture.tagesgeld)
        let (planned, _) = fixture.spied()
        #expect(planned.scheduledSummary == "Geplant · 1")
        #expect(!planned.scheduler.isVisible)
        planned.scheduledToggleClicked()
        #expect(planned.scheduler.isVisible)
        #expect(planned.scheduledSummary == "Geplant · 1")
        #expect(fixture.spied(selection: .allAccounts).model.scheduledSummary == "Geplant · 2")
    }

    @Test func ansichtOffersTheListOnlyWhileNothingIsPlanned() {
        let (planned, _) = fixture().spied()
        #expect(!planned.viewMenu.contains { $0.kind == .action(.toggleScheduler) })
        #expect(!planned.touchViewMenu(showsColumns: false).contains { $0.kind == .action(.toggleScheduler) })
        let (empty, _) = RegisterFixture().spied()
        #expect(empty.scheduledSummary == nil)
        #expect(!empty.scheduler.isVisible)
        #expect(empty.viewMenu.contains { $0.kind == .action(.toggleScheduler) && !$0.isChecked })
        let touchItem = empty.touchViewMenu(showsColumns: false).first { $0.kind == .action(.toggleScheduler) }
        #expect(touchItem?.title == "Geplante Buchungen")
        empty.performMenuAction(.toggleScheduler)
        #expect(empty.scheduler.isVisible)
        #expect(empty.viewMenu.contains { $0.kind == .action(.toggleScheduler) && $0.isChecked })
        #expect(empty.scheduler.rows.isEmpty)
        #expect(empty.scheduler.canAddTransactions)
    }

    @Test func aReconciliationHidesTheCount() {
        let (model, _) = fixture().spied()
        model.reconciliation.reconcileClicked()
        let form = model.reconciliation.statementForm
        form?.amountText = "0"
        if let form { model.reconciliation.begin(form) }
        #expect(model.isReconciling)
        #expect(model.scheduledSummary == nil)
    }

    @Test func touchScreensOpenTheListByHand() {
        let (model, _) = fixture().spied()
        model.isTouch = true
        #expect(!model.isSchedulerVisible)
        model.scheduledToggleClicked()
        #expect(model.isSchedulerVisible)
    }

    @Test func thePaneKeepsItsMinimumHeight() {
        let (model, _) = fixture().spied()
        #expect(model.scheduler.savedHeight == 185)
        model.scheduler.setHeight(120)
        #expect(model.scheduler.savedHeight == 185)
        model.scheduler.setHeight(260)
        #expect(model.scheduler.savedHeight == 260)
        #expect(SchedulerMetrics.height(saved: 600, available: 700) == CGFloat(700 - 1 - 250))
    }

    @Test func newScheduledTransactionDefaultsToMonthlyAndSavesAsSchedule() throws {
        let fixture = RegisterFixture()
        let (model, store) = fixture.spied(appliesCommands: true)
        model.scheduler.grid.beginNew()
        let editor = try #require(model.scheduler.editor)
        #expect(editor.isScheduled)
        #expect(editor.repeats == .monthly)
        #expect(editor.text(.main(.date)) == "20/05/14")
        editor.repeatChosen(.yearly)
        editor.press(.tab)
        #expect(editor.focus == .field(.main(.payee)))
        editor.type("Gym")
        editor.press(.tab, .tab, .tab)
        editor.type("30")
        editor.activate(.save)
        guard case .saveScheduledTransaction(let save) = try #require(store.commands.last) else {
            Issue.record("no schedule saved")
            return
        }
        #expect(save.isNew)
        #expect(save.repeats == .yearly)
        #expect(save.transaction.amount == -30)
        #expect(save.payeeName == "Gym")
        #expect(model.transactions.count == 1)
        #expect(model.scheduler.selectedIds == [save.transaction.id])
    }

    @Test func saveAndAddAnotherStartsTheNextScheduleFromTheSavedOne() throws {
        let fixture = RegisterFixture()
        let (model, store) = fixture.spied(selection: .allAccounts, appliesCommands: true)
        model.scheduler.grid.beginNew()
        let editor = try #require(model.scheduler.editor)
        editor.fieldClicked(.main(.account))
        editor.retype("Ta")
        editor.press(.tab)
        editor.retype("25/05/14")
        editor.repeatChosen(.yearly)
        editor.press(.tab)
        editor.type("Gym")
        editor.press(.tab, .tab, .tab)
        editor.type("30")
        editor.activate(.saveAndAddAnother)
        #expect(store.commands.count == 1)
        guard case .saveScheduledTransaction(let save) = store.commands.first else { return }
        #expect(save.repeats == .yearly)
        #expect(save.transaction.accountId == fixture.tagesgeld)
        let next = try #require(model.scheduler.editor)
        #expect(next !== editor)
        #expect(next.mode == .new)
        #expect(next.repeats == .monthly)
        #expect(next.clone.accountId == fixture.tagesgeld)
        #expect(next.text(.main(.date)) == "25/05/14")
        next.activate(.cancel)
        model.scheduler.grid.beginNew()
        #expect(model.scheduler.editor?.text(.main(.date)) == "25/05/14")
    }

    @Test func addingInAllAccountsStartsInTheFirstOpenAccountAndOffersTheAccountField() throws {
        var fixture = RegisterFixture()
        fixture.budget.accounts[0].closed = true
        let (model, _) = fixture.spied(selection: .allAccounts)
        model.scheduler.grid.beginNew()
        let editor = try #require(model.scheduler.editor)
        #expect(editor.clone.accountId == fixture.tagesgeld)
        #expect(model.scheduler.visibleColumns.first == .account)
        #expect(editor.mainColumns().first == .account)
    }

    @Test func theRepeatChoicesMapToAUnitAndACount() throws {
        let (model, store) = fixture().spied()
        model.scheduler.beginEditing("S1")
        let editor = try #require(model.scheduler.editor)
        #expect(editor.repeatChoice == .monthly)
        #expect(!editor.showsCustomRepeat)
        editor.repeatChosen(.yearly)
        #expect(editor.repeats == .every(12, .month))
        editor.repeatChosen(.once)
        #expect(editor.repeats == .once)
        #expect(editor.followingDatesText == nil)
        editor.repeatChosen(.monthly)
        #expect(editor.repeats == .every(1, .month))
        editor.repeatChosen(.custom)
        #expect(editor.repeats == .every(2, .week))
        #expect(editor.showsCustomRepeat)
        #expect(editor.customRepeatText == "2 Wochen")
        editor.repeatCountChosen(3)
        editor.repeatUnitChosen(.month)
        #expect(editor.repeats == .every(3, .month))
        editor.repeatChosen(.custom)
        #expect(editor.repeats == .every(3, .month))
        editor.repeatCountChosen(100)
        #expect(editor.repeats == .every(3, .month))
        editor.repeatCountChosen(12)
        #expect(editor.repeatChoice == .custom)
        #expect(editor.hasChanges)
        editor.activate(.done)
        guard case .saveScheduledTransaction(let save) = try #require(store.commands.last) else {
            Issue.record("no schedule saved")
            return
        }
        #expect(!save.isNew)
        #expect(save.transaction.id == "S1")
        #expect(save.repeats == .every(12, .month))
    }

    @Test func eigeneStartsAtEveryTwoWeeksAndListsTheNextThreeDates() throws {
        let (model, _) = fixture(on: "2014-06-02").spied()
        model.scheduler.beginEditing("S1")
        let editor = try #require(model.scheduler.editor)
        #expect(editor.followingDatesText == "Danach: 02/07/2014 · 02/08/2014 · 02/09/2014")
        editor.repeatChosen(.custom)
        #expect(editor.followingDatesText == "Danach: 16/06/2014 · 30/06/2014 · 14/07/2014")
        #expect(editor.customCount == 2 && editor.customUnit == .week)
        editor.repeatCountChosen(1)
        #expect(editor.customRepeatText == "1 Woche")
        #expect(TransactionEditor.unitLabel(editor.customUnit, count: editor.customCount) == "Woche")
    }

    @Test func aDateBeforeTodayIsRejected() throws {
        let (model, store) = fixture().spied()
        model.scheduler.beginEditing("S1")
        let editor = try #require(model.scheduler.editor)
        editor.retype("19/05/14")
        editor.press(.tab)
        #expect(
            editor.dateCallout?.message
                == "Datum außerhalb des Bereichs: „<b>19/05/14</b>“<br/>Geplante Buchungen beginnen frühestens heute.")
        #expect(editor.text(.main(.date)) == "02/06/14")
        #expect(store.commands.isEmpty)
    }

    @Test func theDatePickerRefusesADateBeforeTodayAsTypingDoes() throws {
        let (model, store) = fixture().spied()
        model.scheduler.beginEditing("S1")
        let editor = try #require(model.scheduler.editor)
        editor.toggleCalendar()
        editor.calendarDatePicked(day("2014-05-02"))
        #expect(
            editor.dateCallout?.message
                == "Datum außerhalb des Bereichs: „<b>02/05/14</b>“<br/>Geplante Buchungen beginnen frühestens heute.")
        #expect(editor.clone.date == day("2014-06-02"))
        #expect(editor.text(.main(.date)) == "02/06/14")
        #expect(!editor.isCalendarOpen)
        #expect(store.commands.isEmpty)
    }

    @Test func enterNowAddsAnApprovedTransactionAndSelectsIt() throws {
        let fixture = fixture(repeats: .once)
        let (model, store) = fixture.spied(appliesCommands: true)
        let row = try #require(model.scheduler.rows.first)
        model.scheduler.grid.rowClicked(row.transactionId, column: .payee, modifiers: [])
        #expect(model.scheduler.menuTitle == "1 ausgewählte geplante Buchung")
        model.scheduler.enterNowClicked()
        #expect(
            store.commands == [
                .enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true))
            ])
        let entered = try #require(model.transactions.first { $0.source == .scheduled })
        #expect(model.selectedTransactionIds == [entered.id])
        #expect(model.scheduler.selection.isEmpty)
        #expect(model.grid.scrollRequest?.target == .row(entered.id))
    }

    @Test func skipAndDeleteWorkOnTheSelection() throws {
        let (model, store) = fixture().spied()
        let row = try #require(model.scheduler.rows.first)
        model.scheduler.grid.rowClicked(row.transactionId, column: .payee, modifiers: [])
        model.scheduler.skipClicked()
        model.scheduler.deleteClicked()
        model.dialogs.presented.last?.answer(DeleteChoice.delete)
        #expect(store.commands == [.skipScheduledTransactions(["S1"]), .deleteScheduledTransactions(["S1"])])
    }

    @Test func deletingFromTheMenuAsksOnce() throws {
        var fixture = fixture()
        fixture.addSchedule("S2", on: "2014-06-05")
        let (model, store) = fixture.spied()
        model.scheduler.performMenuAction(.deleteScheduled, on: ["S1"])
        let question = try #require(model.dialogs.presented.last)
        #expect(question.dialog.instruction == "Geplante Buchung löschen?")
        question.answer(DeleteChoice.cancel)
        #expect(store.commands.isEmpty)
        model.scheduler.performMenuAction(.deleteScheduled, on: ["S1", "S2"])
        #expect(model.dialogs.presented.last?.dialog.instruction == "2 geplante Buchungen löschen?")
        model.dialogs.presented.last?.answer(DeleteChoice.delete)
        #expect(store.commands == [.deleteScheduledTransactions(["S1", "S2"])])
        #expect(!model.dialogs.isPresenting)
    }

    @Test func moveIntoTheTransferTargetIsRefused() throws {
        var fixture = RegisterFixture()
        fixture.addSchedule("S2", -50, payee: nil, target: fixture.tagesgeld)
        let (model, store) = fixture.spied()
        let row = try #require(model.scheduler.rows.first)
        model.scheduler.contextClicked(row)
        #expect(model.scheduler.moveTargets.map(\.name) == ["Depot", "Karte", "Tagesgeld"])
        store.fail(with: BudgetError.transferIntoMoveTarget("Tagesgeld"), once: true)
        model.scheduler.moveClicked(to: fixture.tagesgeld)
        #expect(
            model.dialogs.presented.last?.dialog.instruction
                == "Nicht alle diese Buchungen lassen sich nach „Tagesgeld“ verschieben.")
        model.dialogs.presented.last?.answer(MessageChoice.close)
        #expect(!model.dialogs.isPresenting)
        #expect(model.notifiers.undoSlot == nil)
        model.scheduler.moveClicked(to: fixture.karte)
        #expect(store.commands.last == .moveScheduledTransactions(["S2"], toAccount: fixture.karte))
        #expect(model.notifiers.undoSlot?.message == "Buchung nach „Karte“ verschoben")
    }

    @Test func rowMenuListsTheScheduledActionsUnderTheSelectionCount() throws {
        let (model, _) = fixture().spied()
        let row = try #require(model.scheduler.rows.first)
        let items = try #require(model.scheduler.contextMenu(for: row))
        #expect(model.scheduler.selectedIds == ["S1"])
        #expect(
            items.map(\.title) == [
                "1 ausgewählte geplante Buchung", "", "Jetzt buchen", "Überspringen", "", "Löschen …", "",
                "In Konto verschieben",
            ])
        #expect(items[0].kind == .title && !items[0].isEnabled)
        #expect(items.filter { $0.kind == .separator }.count == 3)
        #expect(items.dropFirst().allSatisfy { $0.isEnabled })
        #expect(items.last?.submenu?.map(\.title) == ["Depot", "Karte", "Tagesgeld"])
    }

    @Test func jetztBuchenIsOffMenuAndSwipeInAnAccountThatTakesNoEntries() throws {
        var fixture = fixture()
        let index = try #require(fixture.budget.accounts.firstIndex { $0.id == fixture.giro })
        fixture.budget.accounts[index].sharedExpenses = true
        let (model, _) = fixture.spied()
        let row = try #require(model.scheduler.rows.first)
        let items = try #require(model.scheduler.contextMenu(for: row))
        #expect(items.item(titled: "Jetzt buchen")?.isEnabled == false)
        #expect(model.scheduler.actionsMenu(for: ["S1"]).item(titled: "Jetzt buchen")?.isEnabled == false)
        #expect(!model.scheduler.canEnter(["S1"]))
        #expect(items.item(titled: RegisterScheduler.skipTitle)?.isEnabled == true)
    }

    @Test func moveToAccountIsDisabledWithoutATarget() throws {
        var fixture = fixture()
        for index in 1..<fixture.budget.accounts.count { fixture.budget.accounts[index].closed = true }
        let (model, _) = fixture.spied()
        let row = try #require(model.scheduler.rows.first)
        let items = try #require(model.scheduler.contextMenu(for: row))
        #expect(items.item(titled: "In Konto verschieben")?.isEnabled == false)
        #expect(items.item(titled: "In Konto verschieben")?.submenu == [])
    }

    @Test func aChangedEditSwallowsTheRowMenu() throws {
        var fixture = fixture()
        fixture.addSchedule("S2", on: "2014-06-05")
        let (model, _) = fixture.spied()
        model.scheduler.beginEditing("S1", column: .memo)
        model.scheduler.editor?.type("changed")
        let other = try #require(model.scheduler.rows.first { $0.id == "S2" })
        #expect(model.scheduler.contextMenu(for: other) == nil)
        #expect(model.scheduler.editor?.glowCount == 1)
        #expect(model.scheduler.selectedIds == ["S1"])
    }

    @Test(arguments: [
        RegisterMenuAction.enterScheduledNow, .skipScheduled, .deleteScheduled, .moveScheduled(accountId: "KARTE"),
    ])
    func eachRowMenuActionReachesTheScheduler(_ action: RegisterMenuAction) throws {
        let (model, store) = fixture().spied()
        let row = try #require(model.scheduler.rows.first)
        let items = try #require(model.scheduler.contextMenu(for: row))
        func offers(_ items: [RegisterMenuItem]) -> Bool {
            items.contains { $0.kind == .action(action) || offers($0.submenu ?? []) }
        }
        #expect(offers(items))
        model.performMenuAction(action)
        model.dialogs.presented.last?.answer(DeleteChoice.delete)
        let expected: BudgetCommand =
            switch action {
            case .enterScheduledNow:
                .enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true))
            case .skipScheduled: .skipScheduledTransactions(["S1"])
            case .deleteScheduled: .deleteScheduledTransactions(["S1"])
            default: .moveScheduledTransactions(["S1"], toAccount: "KARTE")
            }
        #expect(store.commands == [expected])
    }

    @Test func clickingTheMainGridClearsTheSchedulerSelection() throws {
        let fixture = fixture()
        let (model, _) = fixture.spied()
        let scheduled = try #require(model.scheduler.rows.first)
        model.scheduler.grid.rowClicked(scheduled.transactionId, column: .payee, modifiers: [])
        let row = try #require(model.rows.first)
        model.rowClicked(row, column: .payee, modifiers: [])
        #expect(model.scheduler.selection.isEmpty)
        #expect(model.selectedTransactionIds == [row.transactionId])
    }

    @Test func plusStartsANewScheduledTransactionInASheet() throws {
        let (model, _) = RegisterFixture().spied()
        model.scheduler.addClicked()
        let editor = try #require(model.scheduler.editor)
        #expect(editor.mode == .new)
        #expect(editor.isScheduled)
        #expect(model.scheduler.grid.inlineEditor == nil)
        #expect(model.scheduler.grid.addRowHeight == 0)
        editor.activate(.cancel)
        #expect(model.scheduler.editor == nil)
    }

    @Test func aDoubleClickOpensTheSheetAndASingleClickOnlySelects() throws {
        let (model, _) = fixture().spied()
        model.scheduler.grid.rowClicked("S1", column: .payee, modifiers: [])
        model.scheduler.grid.rowClicked("S1", column: .payee, modifiers: [])
        #expect(model.scheduler.editor == nil)
        #expect(model.scheduler.selectedIds == ["S1"])
        model.scheduler.grid.rowDoubleClicked("S1")
        #expect(model.scheduler.editor?.transactionId == "S1")
        #expect(model.scheduler.grid.editingId == nil)
    }

    @Test func deletingFromTheSheetAsksOnce() throws {
        let (model, store) = fixture().spied()
        model.scheduler.beginEditing("S1")
        model.scheduler.deleteEditedClicked()
        let question = try #require(model.dialogs.presented.last)
        #expect(question.dialog.instruction == "Geplante Buchung löschen?")
        question.answer(DeleteChoice.delete)
        #expect(store.commands.last == .deleteScheduledTransactions(["S1"]))
        #expect(model.scheduler.editor == nil)
    }

    @Test func theRepeatColumnFitsTheLongestRepeat() throws {
        var fixture = fixture()
        let before = fixture.spied().model
        let monthly = try #require(before.scheduler.columnLayout(gridWidth: 1000).frame(of: .repeats))
        #expect(
            monthly.width
                == RegisterColumn.repeats.contentWidth(fitting: ["Monatlich"]))
        fixture.addSchedule("S2", payee: "Gym", repeats: .every(2, .month))
        let after = fixture.spied().model
        let layout = after.scheduler.columnLayout(gridWidth: 1000)
        let longest = try #require(layout.frame(of: .repeats))
        #expect(
            longest.width
                == RegisterColumn.repeats.contentWidth(fitting: ["Alle 2 Monate"]))
        #expect(longest.width > monthly.width)
        let columnsWidth = layout.displayWidth - RegisterMetrics.leadingInset
        #expect(abs(layout.frames.map(\.width).reduce(0, +) - columnsWidth) <= 1)
    }

    @Test func amountColumnsWidenForLargeAmountsAndKeepTheirMinimum() throws {
        var fixture = fixture()
        let before = fixture.spied().model
        let small = before.scheduler.columnLayout(gridWidth: 1000)
        #expect(small.frame(of: .amount)?.width == RegisterColumn.signedAmountWidth)
        #expect(small.frame(of: .date)?.width == RegisterColumn.date.minWidth)
        fixture.addSchedule("S2", -1_234_567.89, payee: "House")
        let after = fixture.spied().model
        let large = after.scheduler.columnLayout(gridWidth: 1000)
        let amount = try #require(large.frame(of: .amount))
        #expect(
            amount.width
                == RegisterColumn.amount.contentWidth(
                    fitting: ["−1,234,567.89", "−25.00"], accessory: EditCellStyle.accessoryWidth))
        #expect(amount.width > RegisterColumn.signedAmountWidth)
    }

    @Test func touchActionsActOnTheScheduleTheyName() {
        var fixture = fixture()
        fixture.addSchedule("S2", on: "2014-06-10", payee: "Gym")
        let (model, store) = fixture.spied()
        model.scheduler.performMenuAction(.skipScheduled, on: ["S2"])
        model.scheduler.performMenuAction(.enterScheduledNow, on: ["S1"])
        #expect(
            store.commands == [
                .skipScheduledTransactions(["S2"]),
                .enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true)),
            ])
    }

    @Test func theTouchMenuOffersTheScheduledActionsWithoutATitle() {
        let (model, _) = fixture().spied()
        let titles = model.scheduler.actionsMenu(for: ["S1"]).filter { $0.kind != .separator }.map(\.title)
        #expect(titles == ["Jetzt buchen", "Überspringen", "Löschen", "In Konto verschieben"])
    }

    @Test func theTouchMenuIsBuiltForTheRowsItNames() throws {
        let (model, _) = fixture().spied(selection: .allAccounts)
        #expect(model.scheduler.actionsMenu(for: ["GONE"]).isEmpty)
        let move = try #require(model.scheduler.actionsMenu(for: ["S1"]).first { $0.id == "move" })
        guard case .submenu(let targets) = move.kind else {
            Issue.record("no submenu")
            return
        }
        #expect(targets.map(\.title) == ["Depot", "Karte", "Tagesgeld"])
    }
}

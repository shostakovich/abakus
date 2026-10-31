import Foundation
import Testing

@testable import AbakusCore

@Suite struct CategoryCommandTests {
    typealias S = ScenarioBudget

    private func layout(_ budget: Budget) -> [String] {
        budget.budgetCategoryGroups.map { master in
            ([master.name] + master.categories.map(\.name)).joined(separator: "|")
        }
    }

    @Test func newMastersGoFirstWithTheFirstFreeName() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.addCategoryGroup(groupId: "N1"))
        try budget.apply(.renameCategoryGroup(groupId: "N1", name: "neue kategoriegruppe"))
        try budget.apply(.addCategoryGroup(groupId: "N2"))
        #expect(
            layout(budget) == [
                "Neue Kategoriegruppe 2", "neue kategoriegruppe", "Alltag|Lebensmittel|Kleidung", "Sparen|Notgroschen",
            ])
        #expect(budget.categoryGroup(withId: "N2")?.categories.isEmpty == true)
    }

    @Test func newSubCategoriesAreAppendedAndExpandTheirMaster() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.setCategoryGroupExpanded(groupId: S.alltag, false))
        try budget.apply(.addCategory(groupId: S.alltag, categoryId: "C1"))
        try budget.apply(.addCategory(groupId: S.alltag, categoryId: "C2"))
        #expect(layout(budget)[0] == "Alltag|Lebensmittel|Kleidung|Neue Kategorie|Neue Kategorie 2")
        #expect(!budget.collapsedCategoryGroupIds.contains(S.alltag))
        for special in [EntityID.uncategorizedMasterCategory, EntityID.incomeMasterCategory] {
            #expect(throws: BudgetError.categoryNotFound(special)) {
                try budget.apply(.addCategory(groupId: special, categoryId: "C3"))
            }
        }
    }

    @Test func masterNamesFollowTheCalloutRulesInOrder() throws {
        var budget = ScenarioBudget().budget
        let cases: [(String, BudgetError)] = [
            ("   ", .categoryMustHaveName), ("A:B", .categoryIllegalCharacters),
            ("In`come", .categoryIllegalCharacters),
            (" einnahmen ", .categoryCantBeIncome), ("__Internal__", .categoryIsReserved),
            ("SPAREN", .categoryNameUsed),
            ("Nicht kategorisiert", .categoryNameUsed),
        ]
        for (name, error) in cases {
            #expect(throws: error) { try budget.apply(.renameCategoryGroup(groupId: S.alltag, name: name)) }
        }
        #expect(BudgetError.categoryMustHaveName.errorDescription == "Die Kategorie braucht einen Namen.")
        #expect(BudgetError.categoryNameUsed.errorDescription == "Diesen Kategorienamen gibt es schon.")
        try budget.apply(.renameCategoryGroup(groupId: S.alltag, name: "  ALLTAG "))
        #expect(budget.categoryGroup(withId: S.alltag)?.name == "ALLTAG")
    }

    @Test func subNamesAreTrimmedAndUniqueWithinTheirMasterOnly() throws {
        var budget = ScenarioBudget().budget
        #expect(throws: BudgetError.categoryMustHaveName) {
            try budget.apply(.renameCategory(categoryId: S.kleidung, name: " "))
        }
        #expect(throws: BudgetError.categoryIllegalCharacters) {
            try budget.apply(.renameCategory(categoryId: S.kleidung, name: "Kleid:ung"))
        }
        #expect(throws: BudgetError.categoryNameUsed) {
            try budget.apply(.renameCategory(categoryId: S.kleidung, name: "lebensmittel"))
        }
        try budget.apply(.renameCategory(categoryId: S.kleidung, name: " Notgroschen "))
        #expect(budget.category(withId: S.kleidung)?.name == "Notgroschen")
    }

    @Test func deletingACategoryMovesEverythingThatUsedItIntoTheSuccessor() throws {
        var scenario = try S.scenarioB()
        try scenario.split([(-10, S.kleidung), (-5, S.lebensmittel)], on: "2026-10-20", payee: "Kaufhaus", id: "SPLIT")
        try scenario.budget(20, S.kleidung, in: "2026-11-01")
        scenario.budget.scheduledTransactions = [
            ScheduledTransaction(
                id: "SCHED", accountId: S.giro, nextDate: date("2026-11-02"), categoryId: S.kleidung, amount: -9),
            ScheduledTransaction(
                id: "SCHED-SPLIT", accountId: S.giro, nextDate: date("2026-11-03"), amount: -9,
                subtransactions: [
                    Subtransaction(transactionId: "SCHED-SPLIT", amount: -9, categoryId: S.kleidung)
                ]),
        ]
        let payee = try #require(scenario.budget.payees.first { $0.name == "Laden" })
        try scenario.budget.apply(.setPayeeLastCategory(payeeId: payee.id, categoryId: S.kleidung))
        try scenario.budget.apply(.deleteCategory(categoryId: S.kleidung, into: S.lebensmittel))
        #expect(scenario.budget.category(withId: S.kleidung) == nil)
        #expect(scenario.budget.transactions.allSatisfy { $0.categoryId != S.kleidung })
        #expect(
            scenario.budget.transaction(withId: "SPLIT")?.subtransactions.map(\.categoryId) == [
                S.lebensmittel, S.lebensmittel,
            ])
        #expect(scenario.budget.scheduledTransaction(withId: "SCHED")?.categoryId == S.lebensmittel)
        #expect(
            scenario.budget.scheduledTransaction(withId: "SCHED-SPLIT")?.subtransactions.map(\.categoryId)
                == [S.lebensmittel])
        #expect(scenario.budget.payee(withId: payee.id)?.lastCategoryId == S.lebensmittel)
        #expect(scenario.month("2026-10-01").rowText(S.lebensmittel) == ["350,00", "-215,00", "135,00"])
        #expect(scenario.month("2026-11-01").rowText(S.lebensmittel) == ["20,00", "", "155,00"])
        #expect(scenario.month("2026-10-01").uncategorized.spent == 0)
    }

    @Test func theSuccessorKeepsItsTargetsAndTheDeletedCategorysGo() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.setTarget(month: october24, categoryId: S.kleidung, target: .monthly(50)))
        try budget.apply(.setTargetSnoozed(month: october24, categoryId: S.kleidung, true))
        try budget.apply(.setTarget(month: october24, categoryId: S.lebensmittel, target: .monthly(300)))
        try budget.apply(.deleteCategory(categoryId: S.kleidung, into: S.lebensmittel))
        #expect(budget.target(in: october24, categoryId: S.lebensmittel) == .monthly(300))
        #expect(!budget.targetVersions.contains { $0.categoryId == S.kleidung })
        #expect(budget.targetSnoozes.isEmpty)
    }

    @Test func aCategoryIsDeletedOnlyIntoAnotherBudgetCategory() throws {
        var budget = ScenarioBudget().budget
        for successor in [S.kleidung, EntityID.uncategorizedCategory, ScenarioBudget.readyToAssign, "GONE"] {
            #expect(throws: BudgetError.categoryNotFound(successor)) {
                try budget.apply(.deleteCategory(categoryId: S.kleidung, into: successor))
            }
        }
        #expect(budget.category(withId: S.kleidung) != nil)
        try budget.apply(.deleteCategory(categoryId: S.kleidung, into: S.notgroschen))
        #expect(budget.category(withId: S.kleidung) == nil)
    }

    @Test func reconciledTransactionsInTheCategoryAreReported() throws {
        var scenario = try S.scenarioB()
        #expect(!scenario.budget.hasReconciledTransactions(inCategory: S.kleidung))
        let split = try scenario.split([(-10, S.kleidung), (-5, S.lebensmittel)], on: "2026-10-20", payee: "Kaufhaus")
        try scenario.budget.apply(.setCleared([split], .reconciled))
        #expect(scenario.budget.hasReconciledTransactions(inCategory: S.kleidung))
        #expect(!scenario.budget.hasReconciledTransactions(inCategory: S.notgroschen))
    }

    @Test func onlyAnEmptyMasterIsDeleted() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.addCategoryGroup(groupId: "N1"))
        try budget.apply(.deleteCategoryGroup(groupId: "N1"))
        #expect(budget.categoryGroup(withId: "N1") == nil)
        #expect(throws: BudgetError.categoryGroupNotEmpty) {
            try budget.apply(.deleteCategoryGroup(groupId: S.sparen))
        }
        #expect(budget.category(withId: S.notgroschen) != nil)
    }

    @Test func onlyAnUnusedCategoryIsDiscarded() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.addCategory(groupId: S.alltag, categoryId: "C"))
        try budget.apply(.discardCategory(categoryId: "C"))
        #expect(budget.category(withId: "C") == nil)
        try budget.apply(.setTarget(month: october24, categoryId: S.notgroschen, target: .monthly(10)))
        #expect(throws: BudgetError.categoryInUse) {
            try budget.apply(.discardCategory(categoryId: S.notgroschen))
        }
    }

    @Test func subCategoriesMoveToTheirDropPosition() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.addCategory(groupId: S.alltag, categoryId: "C"))
        try budget.apply(.moveCategory(categoryId: S.lebensmittel, toGroupId: S.alltag, index: 2))
        #expect(layout(budget)[0] == "Alltag|Kleidung|Lebensmittel|Neue Kategorie")
        try budget.apply(.moveCategory(categoryId: "C", toGroupId: S.alltag, index: 0))
        #expect(layout(budget)[0] == "Alltag|Neue Kategorie|Kleidung|Lebensmittel")
        try budget.apply(.moveCategory(categoryId: "C", toGroupId: S.alltag, index: -1))
        #expect(layout(budget)[0] == "Alltag|Kleidung|Lebensmittel|Neue Kategorie")
    }

    @Test func movingToAnotherMasterKeepsTheBudgetData() throws {
        var scenario = try S.scenarioB()
        try scenario.budget.apply(.moveCategory(categoryId: S.kleidung, toGroupId: S.sparen, index: 0))
        #expect(layout(scenario.budget) == ["Alltag|Lebensmittel", "Sparen|Kleidung|Notgroschen"])
        #expect(scenario.budget.categoryDisplayName(S.kleidung) == "Sparen: Kleidung")
        let october = scenario.month("2026-10-01")
        #expect(october.masterText(S.sparen) == ["50,00", "-80,00", "-30,00"])
        #expect(october.category(S.kleidung)?.assigned == 50)
    }

    @Test func movingOntoASameNamedCategoryIsRefused() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.renameCategory(categoryId: S.notgroschen, name: "kleidung"))
        #expect(throws: BudgetError.categoryNameTakenInGroup(group: "Sparen", name: "Kleidung")) {
            try budget.apply(.moveCategory(categoryId: S.kleidung, toGroupId: S.sparen, index: 0))
        }
        #expect(
            BudgetError.categoryNameTakenInGroup(group: "Sparen", name: "Kleidung").errorDescription
                == "Es gibt schon eine Kategorie „Sparen: Kleidung“.\nBitte eine der beiden umbenennen und es erneut versuchen."
        )
        #expect(throws: BudgetError.categoryNotFound(EntityID.uncategorizedMasterCategory)) {
            try budget.apply(
                .moveCategory(categoryId: S.kleidung, toGroupId: EntityID.uncategorizedMasterCategory, index: 0))
        }
    }

    @Test func mastersMoveToTheirDropPosition() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.addCategoryGroup(groupId: "N"))
        try budget.apply(.moveCategoryGroup(groupId: "N", index: 3))
        #expect(
            layout(budget).map { $0.components(separatedBy: "|")[0] } == ["Alltag", "Sparen", "Neue Kategoriegruppe"])
        try budget.apply(.moveCategoryGroup(groupId: S.sparen, index: 0))
        #expect(
            layout(budget).map { $0.components(separatedBy: "|")[0] } == ["Sparen", "Alltag", "Neue Kategoriegruppe"])
    }

    @Test func expandAllLeavesTheInternalGroupAlone() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.setAllCategoryGroupsExpanded(false))
        #expect(budget.collapsedCategoryGroupIds == Set(budget.budgetCategoryGroups.map(\.id)))
        try budget.apply(.setAllCategoryGroupsExpanded(true))
        #expect(budget.collapsedCategoryGroupIds.isEmpty)
        #expect(throws: BudgetError.categoryNotFound("INTERNAL")) {
            try budget.apply(.setCategoryGroupExpanded(groupId: "INTERNAL", false))
        }
    }
}

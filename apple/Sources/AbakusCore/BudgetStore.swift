import Foundation
import Observation

@MainActor
public protocol BudgetStoring: AnyObject {
    var budget: Budget { get }
    var today: () -> DateWithoutTime { get }
    func perform(_ command: BudgetCommand) throws
}

@MainActor
@Observable
public final class BudgetStore: BudgetStoring {
    public private(set) var budget: Budget
    public private(set) var saveFailures = 0
    public private(set) var hasUnsavedChanges = false
    public private(set) var lastSaveError: String?
    @ObservationIgnored public let database: BudgetDatabase?
    @ObservationIgnored private var savedBudget: Budget?
    @ObservationIgnored public let today: () -> DateWithoutTime
    @ObservationIgnored private let now: () -> Date
    /// A synced budget enters due schedules only once it has pulled what other writers entered.
    @ObservationIgnored private var awaitsPull = false

    public init(
        budget: Budget, database: BudgetDatabase? = nil, today: @escaping () -> DateWithoutTime = { .today() },
        now: @escaping () -> Date = { Date() }
    ) {
        self.budget = budget
        self.database = database
        self.today = today
        self.now = now
    }

    public static func open(
        _ database: BudgetDatabase, today: @escaping () -> DateWithoutTime = { .today() },
        now: @escaping () -> Date = { Date() }
    ) throws -> BudgetStore {
        let day = today()
        let store: BudgetStore
        let unsigned = try database.deviceId == BudgetDatabase.unsignedDevice
        if try unsigned && database.isEmpty {
            store = BudgetStore(budget: DemoBudget.make(today: day), database: database, today: today, now: now)
        } else {
            let loaded = try database.budget()
            store = BudgetStore(budget: loaded, database: database, today: today, now: now)
            store.savedBudget = loaded
            store.awaitsPull = !unsigned
            store.enterDueScheduledTransactions()
            return store
        }
        store.save()
        return store
    }

    public func enterDueScheduledTransactions(today day: DateWithoutTime? = nil) {
        let day = day ?? today()
        guard !awaitsPull, budget.scheduledTransactions.contains(where: { $0.nextDate <= day }) else { return }
        let taken = (try? database?.transactionIds()) ?? []
        try? perform(.enterDueScheduledTransactions(today: day, taken: taken))
    }

    func pulled() {
        awaitsPull = false
        enterDueScheduledTransactions()
    }

    public var databaseURL: URL? { database?.url }

    public var openNotice: String? { database?.openNotice }

    /// Runs after a save that made messages, so they go out.
    @ObservationIgnored public var onChange: () -> Void = {}
    /// Runs after received messages or an adopted snapshot changed the budget.
    @ObservationIgnored public var onReceive: () -> Void = {}

    public func perform(_ command: BudgetCommand) throws {
        let updated = try budget.applying(command)
        guard updated != budget else { return }
        budget = updated
        save()
    }

    /// Unsaved changes are saved first, so the reload loses none.
    public func receive(_ messages: [SyncMessage]) throws {
        guard let database else { return }
        if hasUnsavedChanges { try write() }
        try database.receive(messages)
        try reload(from: database)
    }

    public func adopt(
        _ snapshot: SyncSnapshot, deviceId: String, serverURL: URL, pending: [SyncMessage] = []
    ) throws {
        guard let database else { return }
        let settings = LocalBudgetSettings(budgetName: serverURL.host() ?? serverURL.absoluteString)
        try database.adopt(snapshot, deviceId: deviceId, serverURL: serverURL, settings: settings, pending: pending)
        try reload(from: database)
        pulled()
    }

    public func signOut() throws {
        guard let database else { return }
        try database.reset()
        savedBudget = nil
        awaitsPull = false
        budget = DemoBudget.make(today: today())
        save()
        onReceive()
    }

    private func reload(from database: BudgetDatabase) throws {
        let received = try database.budget()
        savedBudget = received
        guard received != budget else { return }
        budget = received
        onReceive()
    }

    private func save() {
        do {
            try write()
        } catch {
            hasUnsavedChanges = true
            lastSaveError = error.localizedDescription
            saveFailures += 1
        }
    }

    private func write() throws {
        guard let database else { return }
        try? database.backUpOncePerDay(today: today())
        let changed = try database.save(budget, over: savedBudget, now: now())
        savedBudget = budget
        hasUnsavedChanges = false
        lastSaveError = nil
        if changed { onChange() }
    }

    public func retrySave() {
        save()
    }
}

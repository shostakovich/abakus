import AbakusCore
import CoreGraphics
import Foundation

/// The view, search, expanded splits, scrolling and a reconciliation stay session state.
struct SavedRegisterViewState: Codable, Equatable {
    struct Column: Codable, Equatable {
        var visible: Bool
        var width: Double
    }

    struct Sort: Codable, Equatable {
        var column: String
        var ascending: Bool
    }

    var sortColumn: String
    var sortAscending: Bool
    /// Missing before newest first became the default, when every account saved date ascending.
    var sortVersion: Int?
    var schedulerShown: Bool?
    var schedulerHeight: Double?
    var schedulerSort: Sort?
    var schedulerColumns: [String: Column]?

    init(_ state: RegisterAccountViewState) {
        let reconciliation = state.reconciliation
        let sort = reconciliation?.savedSort ?? state.sort
        sortColumn = sort.column.rawValue
        sortAscending = sort.ascending
        sortVersion = Self.currentSortVersion
        schedulerShown = reconciliation.map(\.savedSchedulerShown) ?? state.schedulerShown
        schedulerHeight = state.schedulerHeight.map { Double($0) }
        schedulerSort = Sort(column: state.schedulerSort.column.rawValue, ascending: state.schedulerSort.ascending)
        schedulerColumns = Self.columns(state.schedulerColumnSettings)
    }

    private static func columns(_ settings: RegisterColumnSettings) -> [String: Column] {
        var columns: [String: Column] = [:]
        for column in RegisterColumn.allCases {
            guard let setting = settings[column] else { continue }
            columns[column.rawValue] = Column(visible: setting.visible, width: Double(setting.width))
        }
        return columns
    }

    static func restore(_ saved: [String: Column]?, into settings: inout RegisterColumnSettings) {
        for (name, column) in saved ?? [:] {
            guard let key = RegisterColumn(rawValue: name), settings[key] != nil else { continue }
            settings[key] = RegisterColumnSetting(visible: column.visible, width: CGFloat(column.width))
        }
    }

    static let currentSortVersion = 2

    var restoredSort: RegisterSortOrder? {
        let isOldDefault = sortVersion == nil && sortColumn == RegisterColumn.date.rawValue && sortAscending
        return isOldDefault ? nil : Self.sortOrder(sortColumn, ascending: sortAscending)
    }

    static func sortOrder(_ column: String, ascending: Bool) -> RegisterSortOrder? {
        guard let column = RegisterColumn(rawValue: column) else { return nil }
        return RegisterSortOrder(column: column, ascending: ascending)
    }
}

extension RegisterAccountViewState {
    init(saved: SavedRegisterViewState) {
        self.init()
        sort = saved.restoredSort ?? sort
        schedulerShown = saved.schedulerShown
        schedulerHeight = saved.schedulerHeight.map { CGFloat($0) }
        if let saved = saved.schedulerSort {
            schedulerSort = SavedRegisterViewState.sortOrder(saved.column, ascending: saved.ascending) ?? schedulerSort
        }
        SavedRegisterViewState.restore(saved.schedulerColumns, into: &schedulerColumnSettings)
    }
}

@MainActor
final class RegisterViewStateStore {
    static let key = "RegisterAccountSettings"
    static let hiddenColumnsKey = "RegisterHiddenColumns"

    private let settings: BudgetSettings
    private var saved: [String: SavedRegisterViewState]

    init(settings: BudgetSettings) {
        self.settings = settings
        let data = settings.string(forKey: Self.key).map { Data($0.utf8) }
        saved = data.flatMap { try? JSONDecoder().decode([String: SavedRegisterViewState].self, from: $0) } ?? [:]
    }

    func restored() -> [String: RegisterAccountViewState] {
        saved.mapValues(RegisterAccountViewState.init(saved:))
    }

    var hiddenColumns: Set<RegisterColumn> {
        let names = settings.string(forKey: Self.hiddenColumnsKey).map { $0.split(separator: ",") } ?? []
        return Set(names.compactMap { RegisterColumn(rawValue: String($0)) })
    }

    func saveHiddenColumns(_ columns: Set<RegisterColumn>) {
        settings.set(columns.map(\.rawValue).sorted().joined(separator: ","), forKey: Self.hiddenColumnsKey)
    }

    func save(_ states: [String: RegisterAccountViewState]) {
        let updated = states.mapValues(SavedRegisterViewState.init)
        guard updated != saved, let data = try? JSONEncoder().encode(updated) else { return }
        saved = updated
        settings.set(String(decoding: data, as: UTF8.self), forKey: Self.key)
    }
}

extension RegisterViewModel {
    func restoreViewStates(from store: RegisterViewStateStore) {
        viewStates = store.restored()
        hiddenColumns = store.hiddenColumns
        viewStateStore = store
    }
}

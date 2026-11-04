import AbakusCore
import Foundation

public enum PayeeListFilter: CaseIterable, Hashable, Sendable {
    case listed, hidden, all

    public var title: String {
        switch self {
        case .listed: "Aufgeführte"
        case .hidden: "Ausgeblendete"
        case .all: "Alle"
        }
    }
}

public struct PayeeListSection: Identifiable, Hashable, Sendable {
    static let other = "#"

    public let id: String
    public let rows: [PayeeSettingsModel.Row]

    static func sections(of rows: [PayeeSettingsModel.Row]) -> [PayeeListSection] {
        let grouped = Dictionary(grouping: rows) { initial(of: $0.name) }
        return grouped.keys
            .sorted { $1 == other ? $0 != other : $0 != other && $0 < $1 }
            .map { PayeeListSection(id: $0, rows: grouped[$0] ?? []) }
    }

    static func initial(of name: String) -> String {
        let letter = (name.leadingEmoji?.name ?? name).first.map(String.init) ?? ""
        let folded = letter.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).uppercased()
        return folded.count == 1 && ("A"..."Z").contains(folded) ? folded : other
    }
}

/// iPhone and iPad pick the payee's category from a searchable list instead of typing into the Mac's drop-down.
extension PayeeSettingsModel {
    public func sections(showing filter: PayeeListFilter, matching search: String) -> [PayeeListSection] {
        let search = search.trimmingCharacters(in: .whitespaces)
        let rows = rows.filter { row in
            let shown =
                switch filter {
                case .listed: row.isEnabled
                case .hidden: !row.isEnabled
                case .all: true
                }
            return shown && (search.isEmpty || row.name.localizedCaseInsensitiveContains(search))
        }
        return PayeeListSection.sections(of: rows)
    }

    public func categoryChoices(matching search: String) -> [DropDownItem] {
        DropDownMatching.filter(categoryItems, kind: .category, text: search).filter { $0.kind != .prompt }
    }

    /// An empty value clears the category.
    public func categoryChosen(_ value: String) {
        closeCategoryList()
        categoryText = value
        updateSelectedCategory(askingForNew: false)
    }

    public func newCategoryClicked() {
        closeCategoryList()
        addCategoryForm = AddCategoryForm(masterName: "", name: "")
    }
}

import SwiftUI

/// The budget callouts' menu of categories by group, with an optional row above the groups.
struct BudgetCategoryChoicePicker<Selection: Hashable>: View {
    let label: String
    let groups: [BudgetCategoryChoiceGroup]
    @Binding var selection: Selection
    var leading: (title: String, tag: Selection)?

    var body: some View {
        Picker(label, selection: $selection) {
            if let leading {
                Text(verbatim: leading.title).tag(leading.tag)
            }
            ForEach(groups) { group in
                Section(group.name) {
                    ForEach(group.categories) { Text(verbatim: $0.name).tag($0.id) }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

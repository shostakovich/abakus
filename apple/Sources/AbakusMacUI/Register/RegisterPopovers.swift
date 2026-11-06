import AbakusCore
import AbakusUI
import AppKit
import SwiftUI

struct StatusOptionsPopover: View {
    let model: RegisterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PopoverTitle(model.statusPopupTitle).padding(.horizontal, 8)
            VStack(spacing: 0) {
                ForEach(model.statusPopupOptions) { option in
                    Button {
                        model.statusPopupChosen(option.command)
                    } label: {
                        Text(verbatim: option.title)
                    }
                    .buttonStyle(PopoverMenuButtonStyle())
                }
            }
        }
        .font(ThemeFont.body.font)
        .frame(width: 260, alignment: .leading)
        .closesOnEscape { model.closePopup() }
    }
}

struct NeedsCategoryPopover: View {
    static let visibleRows = 9

    let model: RegisterViewModel
    @State private var chosen: String?

    var body: some View {
        let today = model.today()
        let items = DropDownCatalog(budget: model.store.budget, formatter: model.formatter, today: today)
            .categoryItems(includeSplit: false)
        VStack(alignment: .leading, spacing: 10) {
            PopoverTitle(model.statusPopupTitle)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in row(item) }
                }
                .padding(4)
            }
            .frame(height: CGFloat(Self.visibleRows) * SystemChrome.menuRowHeight + 8)
            .background(ThemeColor.contentBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(ThemeColor.separator) }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Abbrechen") { model.closePopup() }
                Button("Fertig") {
                    if let chosen { model.needsCategoryChosen(chosen) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(chosen == nil)
            }
        }
        .font(ThemeFont.body.font)
        .frame(width: 320)
        .closesOnEscape { model.closePopup() }
    }

    @ViewBuilder
    private func row(_ item: DropDownItem) -> some View {
        switch item.kind {
        case .masterHeader:
            Text(verbatim: item.label)
                .font(ThemeFont.caption.font.weight(.semibold))
                .foregroundStyle(ThemeColor.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: SystemChrome.menuRowHeight, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        case .category(let id, _, _, _):
            let isChosen = chosen == id
            Button {
                chosen = id
            } label: {
                Text(verbatim: item.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isChosen ? AnyShapeStyle(ThemeColor.selectedText) : AnyShapeStyle(ThemeColor.text))
                    .padding(.leading, 20)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, minHeight: SystemChrome.menuRowHeight, alignment: .leading)
                    .background {
                        if isChosen { RoundedRectangle(cornerRadius: 4).fill(ThemeColor.accent) }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isChosen ? .isSelected : [])
        default:
            EmptyView()
        }
    }
}

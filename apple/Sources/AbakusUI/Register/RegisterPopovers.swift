import AbakusCore
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

struct TimeframePopover: View {
    let search: RegisterSearchController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverTitle("Zeitraum")
            TimeframePresetControl(search: search)
            HStack(spacing: 8) {
                Text("Von")
                monthChoice(start: true, label: "Von")
                Text("Bis").padding(.leading, 8)
                monthChoice(start: false, label: "Bis")
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Abbrechen", action: search.timeframeCancelled)
                Button("Fertig", action: search.timeframeDone).buttonStyle(.borderedProminent)
            }
        }
        .font(ThemeFont.body.font)
        .closesOnEscape { search.timeframeCancelled() }
    }

    private func monthChoice(start: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Picker(
                "\(label) Monat",
                selection: Binding(
                    get: { search.timeframeMonth(start: start) ?? 1 },
                    set: { search.setTimeframeMonth(start: start, month: $0) })
            ) {
                ForEach(1...12, id: \.self) { month in Text(verbatim: search.monthName(month)).tag(month) }
            }
            Picker(
                "\(label) Jahr",
                selection: Binding(
                    get: { search.timeframeYear(start: start) ?? 0 },
                    set: { search.setTimeframeYear(start: start, year: $0) })
            ) {
                ForEach(search.timeframeYears, id: \.self) { year in Text(verbatim: String(year)).tag(year) }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// An AppKit segmented control, because SwiftUI's cannot disable a single segment.
private struct TimeframePresetControl: NSViewRepresentable {
    let search: RegisterSearchController

    func makeCoordinator() -> Coordinator { Coordinator(search: search) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: DateFilterPreset.allCases.map(\.label), trackingMode: .selectOne, target: context.coordinator,
            action: #selector(Coordinator.chose(_:)))
        control.setAccessibilityLabel("Zeitraum")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.search = search
        for (index, preset) in DateFilterPreset.allCases.enumerated() {
            control.setEnabled(search.isTimeframePresetEnabled(preset), forSegment: index)
        }
        control.selectedSegment = search.timeframePreset.flatMap(DateFilterPreset.allCases.firstIndex) ?? -1
    }

    @MainActor
    final class Coordinator: NSObject {
        var search: RegisterSearchController

        init(search: RegisterSearchController) {
            self.search = search
        }

        @objc func chose(_ sender: NSSegmentedControl) {
            guard DateFilterPreset.allCases.indices.contains(sender.selectedSegment) else { return }
            search.timeframePresetClicked(DateFilterPreset.allCases[sender.selectedSegment])
        }
    }
}

struct RunningBalancePopover: View {
    let info: RunningBalanceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PopoverTitle(info.title)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(Array(info.lines.enumerated()), id: \.offset) { index, line in
                    if index == info.lines.count - 1 { Divider() }
                    GridRow {
                        Text(verbatim: line.amount)
                            .font(ThemeFont.body.font.monospacedDigit().weight(.semibold))
                            .gridColumnAlignment(.trailing)
                        Text(verbatim: line.caption).foregroundStyle(ThemeColor.secondaryText)
                    }
                }
            }
        }
        .font(ThemeFont.body.font)
        .foregroundStyle(ThemeColor.text)
    }
}

struct ScheduledCalloutPopover: View {
    let callout: RegisterScheduledCallout
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PopoverTitle(callout.title)
            Text(TextMarkup.attributed(callout.message))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button("Schließen", action: onClose)
            }
            .padding(.top, 4)
        }
        .font(ThemeFont.body.font)
        .foregroundStyle(ThemeColor.text)
        .frame(width: 340, alignment: .leading)
    }
}

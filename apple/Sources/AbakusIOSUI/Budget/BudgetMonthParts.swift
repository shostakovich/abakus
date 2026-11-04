#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    enum BudgetTouchStyle {
        static let chevronWidth: CGFloat = 14
        static let chevronSpacing: CGFloat = 6
        /// Category names start where their group's name does, past the chevron.
        static let nameIndent = chevronWidth + chevronSpacing
        static let targetBarHeight: CGFloat = 3
        static let bandCornerRadius: CGFloat = 12
    }

    struct BudgetTitleMenu: View {
        let model: BudgetViewModel
        @State private var isPicking = false

        var body: some View {
            Button {
                isPicking = true
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: model.shownMonthsTitle).font(.headline).lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ThemeColor.secondaryText)
                        .rotationEffect(.degrees(isPicking ? 180 : 0))
                }
                .foregroundStyle(ThemeColor.text)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.shownMonthsTitle)
            .accessibilityHint("Monat wählen")
            .accessibilityAddTraits(.isHeader)
            .popover(isPresented: $isPicking) {
                BudgetMonthPicker(model: model) { isPicking = false }
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(.regularMaterial)
            }
        }
    }

    struct BudgetMonthPicker: View {
        /// Muted, yet 4.5:1 on the material in both themes, which the system's secondary label is not.
        private static let pastText = ThemeColor.text.opacity(0.6)

        let model: BudgetViewModel
        let onPicked: () -> Void
        @State private var year: Int?

        var body: some View {
            let year = self.year ?? model.shownMonths.first?.year ?? 0
            VStack(spacing: 12) {
                HStack {
                    Button("Voriges Jahr", systemImage: "chevron.left") { self.year = year - 1 }
                    Spacer()
                    Text(verbatim: String(year)).font(.headline).monospacedDigit()
                    Spacer()
                    Button("Nächstes Jahr", systemImage: "chevron.right") { self.year = year + 1 }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(model.monthPickerCells(year: year)) { cell in
                        Button {
                            model.select(cell.month)
                            onPicked()
                        } label: {
                            monthLabel(cell)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.formatter.monthHeader(cell.month))
                        .accessibilityAddTraits(cell.isShown ? .isSelected : [])
                    }
                }
                Button("Heute") {
                    model.todayClicked()
                    onPicked()
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .disabled(model.showsTodaysMonth)
            }
            .padding(16)
            .frame(width: 300)
        }

        private func monthLabel(_ cell: BudgetMonthPickerCell) -> some View {
            Text(verbatim: cell.label)
                .font(.body.weight(cell.isCurrent || cell.isShown ? .semibold : .regular))
                .foregroundStyle(
                    cell.isShown
                        ? AnyShapeStyle(ThemeColor.selectedText)
                        : cell.isCurrent
                            ? AnyShapeStyle(ThemeColor.accent)
                            : cell.isPast ? AnyShapeStyle(Self.pastText) : AnyShapeStyle(ThemeColor.text)
                )
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(fill(cell), in: Capsule())
                .contentShape(Capsule())
        }

        private func fill(_ cell: BudgetMonthPickerCell) -> Color {
            cell.isShown ? ThemeColor.accent : .clear
        }
    }

    struct BudgetDistributeMenu: View {
        private struct MenuSection: Identifiable {
            let id: Int
            var title: String?
            var items: [RegisterMenuItem] = []
        }

        let model: BudgetViewModel
        let month: DateWithoutTime

        var body: some View {
            Menu {
                ForEach(sections) { section in
                    if let title = section.title {
                        Section(title) { items(section) }
                    } else {
                        Section { items(section) }
                    }
                }
            } label: {
                Text("Verteilen").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(ThemeColor.positive)
            .foregroundStyle(ThemeColor.positiveContent)
        }

        private func items(_ section: MenuSection) -> some View {
            RegisterMenuItemsView(items: section.items) { model.callouts.quickBudgetMenuChosen($0, month: month) }
        }

        /// The Mac's headings and separators become the menu's sections.
        private var sections: [MenuSection] {
            var sections = [MenuSection(id: 0)]
            for item in model.callouts.quickBudgetMenu(month: month) {
                switch item.kind {
                case .separator:
                    sections.append(MenuSection(id: sections.count))
                case .title:
                    let title = item.title.trimmingCharacters(in: .whitespaces)
                    if sections[sections.count - 1].items.isEmpty {
                        sections[sections.count - 1].title = title
                    } else {
                        sections.append(MenuSection(id: sections.count, title: title))
                    }
                default:
                    var item = item
                    item.title = item.title.trimmingCharacters(in: .whitespaces)
                    sections[sections.count - 1].items.append(item)
                }
            }
            return sections.filter { !$0.items.isEmpty }
        }
    }

    /// One line where it fits, else one part a line; a shorter line keeps a 44 pt tap area.
    struct BudgetWaitingLine: View {
        static let tapHeight: CGFloat = 44

        let model: BudgetViewModel
        let month: BudgetMonth
        let waiting: BudgetWaiting
        var lineHeight = Self.tapHeight

        var body: some View {
            if !waiting.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        overspent
                        if waiting.overspentText != nil && waiting.approvalsText != nil {
                            Text(verbatim: "·").foregroundStyle(ThemeColor.secondaryText).accessibilityHidden(true)
                        }
                        approvals
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        overspent
                        approvals
                    }
                }
                .font(.footnote.weight(.medium))
                .labelStyle(BudgetWaitingLabelStyle())
                .buttonStyle(.plain)
                .lineLimit(1)
            }
        }

        private var tapArea: BudgetWaitingTapArea { BudgetWaitingTapArea(lineHeight: lineHeight) }

        @ViewBuilder
        private var overspent: some View {
            if let text = waiting.overspentText {
                Button {
                    model.overspentTapped(in: month)
                } label: {
                    Label(text, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(ThemeColor.negative)
                        .modifier(tapArea)
                }
            }
        }

        @ViewBuilder
        private var approvals: some View {
            if let text = waiting.approvalsText {
                Button(action: model.approvalsTapped) {
                    Label(text, systemImage: "checkmark.circle")
                        .foregroundStyle(ThemeColor.accent)
                        .modifier(tapArea)
                }
            }
        }
    }

    private struct BudgetWaitingTapArea: ViewModifier {
        let lineHeight: CGFloat

        func body(content: Content) -> some View {
            content
                .frame(minHeight: lineHeight)
                .contentShape(Rectangle().inset(by: -max(0, BudgetWaitingLine.tapHeight - lineHeight) / 2))
        }
    }

    private struct BudgetWaitingLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 4) {
                configuration.icon.imageScale(.small)
                configuration.title
            }
        }
    }

    /// `amountInset` reports how far its amount ends from the block's end, so the calculation lines up.
    struct BudgetResultBand: View {
        nonisolated static let space = "budgetResultBand"

        let model: BudgetViewModel
        let month: BudgetMonth
        var amountInset: Binding<CGFloat>?
        @State private var bandWidth: CGFloat = 0

        var body: some View {
            let display = model.headerDisplay(month)
            let isPositive = display.availableTint == .positive
            HStack(spacing: 12) {
                Button(action: model.toggleHeaderDetails) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        HStack(spacing: 4) {
                            Text(verbatim: month.resultLabel).lineLimit(1).minimumScaleFactor(0.75)
                            Image(systemName: "chevron.down")
                                .imageScale(.small)
                                .rotationEffect(.degrees(model.isHeaderExpanded ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isPositive ? ThemeColor.positive : ThemeColor.text)
                        Spacer(minLength: 0)
                        Text(verbatim: display.available)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(display.availableTint.color)
                            .lineLimit(1)
                            .fixedSize()
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.frame(in: .named(Self.space)).maxX
                            } action: { maxX in
                                amountInset?.wrappedValue = max(0, bandWidth - maxX)
                            }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(model.headerToggleToolTip)
                if isPositive {
                    BudgetDistributeMenu(model: model, month: month.month)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, isPositive ? 8 : 14)
            .frame(minHeight: 48)
            .background(
                isPositive ? ThemeColor.positiveBand : ThemeColor.groupBand,
                in: RoundedRectangle(cornerRadius: BudgetTouchStyle.bandCornerRadius)
            )
            .coordinateSpace(.named(Self.space))
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { bandWidth = $0 }
        }
    }

    struct BudgetCalculation: View {
        let model: BudgetViewModel
        let month: BudgetMonth
        var lineCount = 0
        var amountInset: CGFloat = 14
        var horizontalPadding: CGFloat = 0

        var body: some View {
            let lines = month.headerLines(formatter: model.formatter, withUnit: true)
            VStack(spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: line.text)
                            .foregroundStyle(line.isWarning ? ThemeColor.negative : ThemeColor.secondaryText)
                        Spacer(minLength: 8)
                        Text(verbatim: line.amount)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(line.isWarning ? ThemeColor.negative : ThemeColor.text)
                    }
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                }
                ForEach(lines.count..<max(lines.count, lineCount), id: \.self) { _ in
                    Text(verbatim: " ").accessibilityHidden(true)
                }
            }
            .font(.footnote)
            .padding(.leading, 14 + horizontalPadding)
            .padding(.trailing, amountInset + horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(ThemeColor.groupBand, ignoresSafeAreaEdges: [])
            .overlay(alignment: .top) { Rectangle().fill(ThemeColor.separator).frame(height: 0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(ThemeColor.separator).frame(height: 0.5) }
        }
    }

    /// The mark keeps its slot even when empty, so the digits line up. Without the ring the mark follows the bar.
    struct BudgetAvailableFigure: View {
        let display: BudgetSubRowDisplay
        let month: BudgetMonth
        var showsRing = true
        var amountWidth: CGFloat?

        var body: some View {
            HStack(spacing: 4) {
                Text(verbatim: display.balance)
                    .fontWeight(display.isBalanceZero ? .regular : .semibold)
                    .monospacedDigit()
                    .foregroundStyle(style)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: amountWidth, alignment: .trailing)
                Color.clear.frame(width: BudgetStyle.ringSize, height: BudgetStyle.ringSize).overlay { marker }
            }
        }

        @ViewBuilder
        private var marker: some View {
            if let marker = showsRing ? display.marker : display.barMarker {
                let color = month.isClosed ? ThemeColor.secondaryText : marker.symbol.color
                if let percent = display.fundedPercent {
                    if showsRing { BudgetTargetRing(percent: percent, color: color) }
                } else {
                    Image(systemName: marker.symbol.name).font(.caption2).foregroundStyle(color)
                }
            }
        }

        private var style: AnyShapeStyle {
            if display.isBalanceZero { return AnyShapeStyle(ThemeColor.tertiaryText) }
            if display.isBalanceNegative { return AnyShapeStyle(ThemeColor.negative) }
            if month.isClosed { return AnyShapeStyle(ThemeColor.secondaryText) }
            return display.marker == .underfunded ? AnyShapeStyle(ThemeColor.warning) : AnyShapeStyle(ThemeColor.text)
        }
    }

    struct BudgetTargetBarView: View {
        let bar: BudgetTargetBar

        var body: some View {
            Capsule()
                .fill(ThemeColor.targetTrack)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(color).frame(width: proxy.size.width * bar.share)
                    }
                }
                .frame(height: BudgetTouchStyle.targetBarHeight)
                .accessibilityHidden(true)
        }

        private var color: Color {
            switch bar.state {
            case .underfunded: ThemeColor.warning
            case .funded: ThemeColor.positive
            case .overspent: ThemeColor.negative
            case .snoozed, .idle: ThemeColor.secondaryText
            }
        }
    }

    struct BudgetGroupLabel<Trailing: View>: View {
        let model: BudgetViewModel
        let group: BudgetGroup
        @ViewBuilder let trailing: Trailing

        var body: some View {
            let header = group.header
            Button {
                model.disclosureClicked(header.id)
            } label: {
                HStack(spacing: BudgetTouchStyle.chevronSpacing) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ThemeColor.secondaryText)
                        .rotationEffect(.degrees(group.isExpanded ? 90 : 0))
                        .frame(width: BudgetTouchStyle.chevronWidth)
                        .accessibilityHidden(true)
                    BudgetCategoryName(name: header.name, weight: .semibold)
                    Spacer(minLength: 8)
                    trailing
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(group.isExpanded ? "Aufgeklappt" : "Zugeklappt")
            .contextMenu {
                Button("Gruppe bearbeiten …", systemImage: "pencil") { model.categoryTapped(header.id) }
                Button("Neue Kategorie", systemImage: "plus") { model.addSubCategoryClicked(masterId: header.id) }
                Divider()
                Button("Alle Gruppen aufklappen", systemImage: "chevron.down", action: model.expandAllClicked)
                Button("Alle Gruppen zuklappen", systemImage: "chevron.up", action: model.collapseAllClicked)
            }
        }
    }

    /// The emoji in a column of its own, so names line up, the separators start at them and so does a target's bar.
    struct BudgetCategoryName: View {
        static let emojiWidth: CGFloat = 26
        static let emojiSpacing: CGFloat = 6

        let name: String
        var weight = Font.Weight.regular
        var bar: BudgetTargetBar?
        @ScaledMetric(relativeTo: .body) private var emojiWidth: CGFloat = Self.emojiWidth

        var body: some View {
            let parts = name.leadingEmoji
            HStack(spacing: Self.emojiSpacing) {
                Text(verbatim: parts?.emoji ?? "")
                    .frame(width: emojiWidth, alignment: .leading)
                    .accessibilityHidden(true)
                Text(verbatim: parts?.name ?? name)
                    .fontWeight(weight)
                    .foregroundStyle(ThemeColor.text)
                    .lineLimit(1)
                    .frame(maxWidth: bar == nil ? nil : .infinity, alignment: .leading)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    .overlay(alignment: .bottomLeading) {
                        if let bar {
                            BudgetTargetBarView(bar: bar).offset(y: BudgetTouchStyle.targetBarHeight + 4)
                        }
                    }
            }
        }
    }

    struct BudgetAddGroupButton: View {
        let model: BudgetViewModel
        @ScaledMetric(relativeTo: .body) private var emojiWidth: CGFloat = BudgetCategoryName.emojiWidth

        var body: some View {
            Button(action: model.addMasterCategoryClicked) {
                HStack(spacing: BudgetCategoryName.emojiSpacing) {
                    Image(systemName: "plus").frame(width: emojiWidth)
                    Text("Neue Kategoriegruppe")
                }
                .padding(.leading, BudgetTouchStyle.nameIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ThemeColor.accent)
            .listRowSeparator(.hidden)
            .moveDisabled(true)
        }
    }

    /// A row of the budget's list: a group's header or one of its categories, in the order a move counts.
    struct BudgetListRow: Identifiable {
        let row: BudgetCategoryRow
        let group: BudgetGroup

        var id: String { row.id }
        var isHeader: Bool { row.kind == .master }
    }

    extension [BudgetGroup] {
        var listRows: [BudgetListRow] {
            flatMap { group in group.visibleRows.map { BudgetListRow(row: $0, group: group) } }
        }
    }
#endif

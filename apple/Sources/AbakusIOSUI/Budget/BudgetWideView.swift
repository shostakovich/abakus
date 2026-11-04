#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct BudgetWideView: View {
        static let rowInsets = EdgeInsets(
            top: 0, leading: BudgetTouchLayout.rowInset, bottom: 0, trailing: BudgetTouchLayout.rowInset)

        let model: BudgetViewModel
        let dialogs: [PresentedDialog]
        let categoryWidth: CGFloat
        @FocusState private var focusedCell: BudgetCellID?

        var body: some View {
            let months = model.shownMonths.compactMap(model.month)
            ScrollViewReader { proxy in
                List {
                    ForEach(model.groups.listRows) { item in
                        row(item, months: months)
                            .listRowInsets(Self.rowInsets)
                            .listRowBackground(
                                BudgetAvailableColumns(
                                    categoryWidth: categoryWidth, monthCount: months.count,
                                    base: item.isHeader ? ThemeColor.groupBand : ThemeColor.contentBackground))
                    }
                    .onMove(perform: model.touchRowsMoved)
                    BudgetAddGroupButton(model: model)
                        .listRowInsets(Self.rowInsets)
                        .listRowBackground(
                            BudgetAvailableColumns(
                                categoryWidth: categoryWidth, monthCount: months.count,
                                base: ThemeColor.contentBackground))
                }
                .listStyle(.plain)
                .scrollsUnderDock()
                .scrollContentBackground(.hidden)
                .background {
                    BudgetAvailableColumns(
                        categoryWidth: categoryWidth, monthCount: months.count, base: ThemeColor.contentBackground
                    )
                    .ignoresSafeArea()
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    BudgetWideHeader(model: model, months: months, categoryWidth: categoryWidth)
                }
                .onChange(of: model.editor?.cell) { _, cell in
                    focusedCell = cell
                    if let cell { withAnimation { proxy.scrollTo(cell.categoryId) } }
                }
                .onChange(of: model.presentedPopup) { _, popup in
                    // A popover needs its row on screen to stand on.
                    if case .category(_, let categoryId) = popup { proxy.scrollTo(categoryId) }
                }
                .onChange(of: focusedCell) { old, new in
                    if new == nil, let old, model.editor?.cell == old { model.commitEdit() }
                }
            }
        }

        @ViewBuilder
        private func row(_ item: BudgetListRow, months: [BudgetMonth]) -> some View {
            switch item.row.kind {
            case .master:
                BudgetWideRow(categoryWidth: categoryWidth, months: months) {
                    BudgetGroupLabel(model: model, group: item.group) { EmptyView() }
                } cells: { month in
                    BudgetWideGroupCells(model: model, row: item.row, month: month)
                }
            case .uncategorized:
                BudgetWideRow(categoryWidth: categoryWidth, months: months) {
                    Button(action: model.uncategorizedTapped) { name(item.row) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Buchungen ohne Kategorie zeigen")
                } cells: { month in
                    BudgetWideGroupCells(model: model, row: item.row, month: month, isCategory: true)
                }
                .moveDisabled(true)
            case .sub:
                BudgetWideRow(categoryWidth: categoryWidth, months: months) {
                    categoryName(item.row)
                } cells: { month in
                    BudgetWideCategoryCells(
                        model: model, row: item.row, month: month, focus: $focusedCell,
                        popover: popover(item.row.id, month: month), dialogs: dialogs)
                }
                .id(item.row.id)
            }
        }

        private func name(_ row: BudgetCategoryRow) -> some View {
            BudgetCategoryName(name: row.name)
                .padding(.leading, BudgetTouchStyle.nameIndent)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }

        /// The popover opens on the month in focus's Verfügbar, as on every other tap.
        private func categoryName(_ row: BudgetCategoryRow) -> some View {
            Button {
                model.categoryTapped(row.id)
            } label: {
                name(row)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Kategorie bearbeiten")
        }

        private func popover(_ categoryId: String, month: BudgetMonth) -> Binding<Bool> {
            let popup = BudgetPopup.category(month: month.month, categoryId: categoryId)
            return Binding {
                model.presentedPopup == popup
            } set: { shown in
                if !shown && model.presentedPopup == popup { model.touchSheetDismissed() }
            }
        }
    }

    /// As tall as its content, up to what the screen leaves; the form scrolls beyond.
    private struct BudgetPopover: View {
        let model: BudgetViewModel
        let dialogs: [PresentedDialog]
        @State private var height: CGFloat?

        var body: some View {
            BudgetSheet(model: model, isPopover: true)
                .modifier(DialogAlert(dialogs: dialogs))
                .environment(\.reportFormHeight, FormHeightReport { height = $0.rounded(.up) })
                .frame(width: 400, height: height ?? 560)
                .presentationCompactAdaptation(.popover)
        }
    }

    private struct BudgetWideRow<Name: View, Cells: View>: View {
        let categoryWidth: CGFloat
        let months: [BudgetMonth]
        var alignment = VerticalAlignment.center
        var showsSeparators = true
        @ViewBuilder let name: Name
        @ViewBuilder let cells: (BudgetMonth) -> Cells

        var body: some View {
            HStack(alignment: alignment, spacing: 0) {
                name.frame(width: categoryWidth, alignment: .leading).frame(minHeight: 44)
                ForEach(months, id: \.month) { month in
                    Rectangle().fill(showsSeparators ? AnyShapeStyle(ThemeColor.separator) : AnyShapeStyle(.clear))
                        .frame(width: 1)
                        .padding(.horizontal, (BudgetTouchLayout.monthGap - 1) / 2)
                    cells(month).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct BudgetAvailableColumns: View {
        /// The tint starts a little before Verfügbar's figures, so they never touch its edge.
        private static let leadingOverhang: CGFloat = 4

        let categoryWidth: CGFloat
        let monthCount: Int
        let base: Color

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    base
                    ForEach(0..<monthCount, id: \.self) { index in
                        let column = Self.column(
                            index, months: monthCount, width: proxy.size.width, category: categoryWidth)
                        ThemeColor.availableTint
                            .frame(width: column.width)
                            .offset(x: column.minX)
                    }
                }
            }
        }

        static func column(_ index: Int, months: Int, width: CGFloat, category: CGFloat) -> (
            minX: CGFloat, width: CGFloat
        ) {
            let inset = BudgetTouchLayout.rowInset
            let gap = BudgetTouchLayout.monthGap
            let spacing = BudgetTouchLayout.figureSpacing
            let cellWidth = BudgetTouchLayout.monthWidth(months: max(months, 1), width: width, categoryWidth: category)
            let cellStart = inset + category + gap * CGFloat(index + 1) + cellWidth * CGFloat(index)
            let figureWidth = (cellWidth - 2 * spacing) / 3
            let minX = cellStart + 2 * (figureWidth + spacing) - leadingOverhang
            let maxX = index == months - 1 ? width : cellStart + cellWidth + gap / 2
            return (minX, max(0, maxX - minX))
        }
    }

    private struct BudgetWideHeader: View {
        static let columnTitles = ["Zugewiesen", "Aktivität", "Verfügbar"]

        let model: BudgetViewModel
        let months: [BudgetMonth]
        let categoryWidth: CGFloat

        var body: some View {
            let lineCount = months.map { $0.headerLines(formatter: model.formatter).count }.max() ?? 0
            VStack(spacing: 0) {
                BudgetWideRow(
                    categoryWidth: categoryWidth, months: months, alignment: .resultBandTop, showsSeparators: false
                ) {
                    if let month = model.monthInFocus {
                        BudgetWaitingLine(
                            model: model, month: month, waiting: model.waiting(in: month), lineHeight: 24
                        )
                        .padding(.leading, BudgetTouchStyle.nameIndent)
                        .padding(.trailing, 8)
                        .alignmentGuide(.resultBandTop) { $0[.top] }
                    }
                } cells: { month in
                    BudgetWideMonthHead(model: model, month: month, lineCount: lineCount, showsTitle: months.count > 1)
                }
                .padding(.horizontal, BudgetTouchLayout.rowInset)
                .padding(.top, 8)
                .padding(.bottom, 10)
                BudgetWideRow(categoryWidth: categoryWidth, months: months, alignment: .bottom) {
                    HStack {
                        Text("Kategorie").font(.footnote).foregroundStyle(ThemeColor.secondaryText)
                        Spacer(minLength: 4)
                        Button("Gruppe", systemImage: "plus", action: model.addMasterCategoryClicked)
                            .font(.footnote.weight(.medium))
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Neue Kategoriegruppe")
                    }
                    .padding(.leading, BudgetTouchStyle.nameIndent)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                } cells: { month in
                    ViewThatFits(in: .horizontal) {
                        totals(month, font: .subheadline.weight(.semibold))
                        totals(month, font: .footnote.weight(.semibold))
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, BudgetTouchLayout.rowInset)
                .background(
                    BudgetAvailableColumns(
                        categoryWidth: categoryWidth, monthCount: months.count, base: ThemeColor.contentBackground))
            }
            .background(ThemeColor.contentBackground)
            .overlay(alignment: .bottom) { Rectangle().fill(ThemeColor.separator).frame(height: 0.5) }
        }

        private func totals(_ month: BudgetMonth, font: Font) -> some View {
            let display = model.headerDisplay(month)
            return BudgetFigureColumns {
                ForEach(0..<3, id: \.self) { index in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: Self.columnTitles[index])
                            .font(.footnote)
                            .foregroundStyle(ThemeColor.secondaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(verbatim: display.totals[index].text)
                            .font(font)
                            .monospacedDigit()
                            .foregroundStyle(display.isPast ? ThemeColor.secondaryText : ThemeColor.text)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.trailing, index == 2 ? BudgetStyle.markerSlot : 0)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private struct BudgetWideMonthHead: View {
        let model: BudgetViewModel
        let month: BudgetMonth
        let lineCount: Int
        let showsTitle: Bool
        @State private var amountInset: CGFloat = 14

        var body: some View {
            let display = model.headerDisplay(month)
            VStack(alignment: .leading, spacing: 8) {
                if showsTitle {
                    Text(verbatim: display.title)
                        .font(.headline)
                        .foregroundStyle(display.isPast ? ThemeColor.secondaryText : ThemeColor.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                if model.isHeaderExpanded {
                    BudgetCalculation(
                        model: model, month: month, lineCount: lineCount, amountInset: amountInset
                    )
                    .clipShape(RoundedRectangle(cornerRadius: BudgetTouchStyle.bandCornerRadius))
                }
                BudgetResultBand(model: model, month: month, amountInset: $amountInset)
                    .alignmentGuide(.resultBandTop) { $0[.top] }
            }
        }
    }

    extension VerticalAlignment {
        /// What waits in the corner starts where Zu verteilen does, also below an open calculation.
        fileprivate enum ResultBandTop: AlignmentID {
            static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.top] }
        }

        fileprivate static let resultBandTop = VerticalAlignment(ResultBandTop.self)
    }

    /// The rows' three equal figure columns; ideally as wide as three of the widest, so every total fits its column.
    private struct BudgetFigureColumns: Layout {
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let widest = sizes.map(\.width).max() ?? 0
            let width = proposal.width ?? CGFloat(subviews.count) * widest + gaps(subviews)
            return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            let width = (bounds.width - gaps(subviews)) / CGFloat(max(subviews.count, 1))
            for (index, subview) in subviews.enumerated() {
                let x = bounds.minX + CGFloat(index) * (width + BudgetTouchLayout.figureSpacing)
                subview.place(
                    at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            }
        }

        private func gaps(_ subviews: Subviews) -> CGFloat {
            BudgetTouchLayout.figureSpacing * CGFloat(max(subviews.count - 1, 0))
        }
    }

    private struct BudgetWideGroupCells: View {
        let model: BudgetViewModel
        let row: BudgetCategoryRow
        let month: BudgetMonth
        var isCategory = false

        var body: some View {
            let display = model.masterRowDisplay(row, in: month)
            HStack(spacing: BudgetTouchLayout.figureSpacing) {
                figure(display.assigned, color: muted)
                figure(display.outflows, color: ThemeColor.secondaryText)
                figure(display.balance, color: display.isBalanceNegative ? ThemeColor.negative : muted)
                    .padding(.trailing, BudgetStyle.markerSlot)
            }
            .fontWeight(isCategory ? .regular : .semibold)
        }

        private var muted: Color { month.isClosed ? ThemeColor.secondaryText : ThemeColor.text }

        private func figure(_ text: String, color: Color) -> some View {
            Text(verbatim: text)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private struct BudgetWideCategoryCells: View {
        let model: BudgetViewModel
        let row: BudgetCategoryRow
        let month: BudgetMonth
        var focus: FocusState<BudgetCellID?>.Binding
        let popover: Binding<Bool>
        let dialogs: [PresentedDialog]

        var body: some View {
            let display = model.subRowDisplay(row.id, in: month)
            let cell = BudgetCellID(month: month.month, categoryId: row.id)
            HStack(spacing: BudgetTouchLayout.figureSpacing) {
                Group {
                    if let edit = model.editor, edit.cell == cell {
                        BudgetAssignedField(model: model, edit: edit, focus: focus)
                    } else {
                        Button {
                            model.beginEdit(cell)
                        } label: {
                            Text(verbatim: display.assigned)
                                .monospacedDigit()
                                .foregroundStyle(month.isClosed ? ThemeColor.secondaryText : ThemeColor.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Zugewiesen")
                        .accessibilityValue(display.assigned.isEmpty ? model.zeroText : display.assigned)
                    }
                }
                .frame(maxWidth: .infinity)
                Text(verbatim: display.outflows)
                    .monospacedDigit()
                    .foregroundStyle(ThemeColor.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Aktivität")
                Button {
                    model.categoryTapped(row.id, month: month.month)
                } label: {
                    BudgetAvailableFigure(display: display, month: month)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Verfügbar")
                .accessibilityValue(display.accessibilityValue)
                .accessibilityAddTraits(.isButton)
                .popover(isPresented: popover, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                    BudgetPopover(model: model, dialogs: dialogs)
                }
            }
        }
    }

    /// With a hardware keyboard Tab, Return and the arrows move between the month's cells and Escape cancels.
    private struct BudgetAssignedField: View {
        let model: BudgetViewModel
        let edit: BudgetCellEdit
        var focus: FocusState<BudgetCellID?>.Binding
        @State private var selection: TextSelection?

        var body: some View {
            TextField(
                "Zugewiesen", text: Binding(get: { model.editor?.text ?? "" }, set: { model.cellTextChanged($0) }),
                selection: $selection
            )
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .keyboardType(.numbersAndPunctuation)
            .submitLabel(.next)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(ThemeColor.fieldBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(ThemeColor.focusRing, lineWidth: 2) }
            .focused(focus, equals: edit.cell)
            .onSubmit { model.cellKey(.enter) }
            .onKeyPress(keys: [.tab, .upArrow, .downArrow, .escape], phases: .down) { press in
                model.cellKey(Self.key(press)) ? .handled : .ignored
            }
            .onChange(of: edit.selectAllRequest, initial: true) {
                selection = TextSelection(range: edit.text.startIndex..<edit.text.endIndex)
            }
        }

        private static func key(_ press: KeyPress) -> BudgetCellKey {
            switch press.key {
            case .upArrow: .up
            case .downArrow: .down
            case .escape: .escape
            default: press.modifiers.contains(.shift) ? .backTab : .tab
            }
        }
    }
#endif

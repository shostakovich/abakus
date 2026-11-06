#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    /// The glyph column belongs to the second line, so the glyphs stand in one row.
    struct RegisterCard: View {
        let register: RegisterViewModel
        let row: RegisterRow
        @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 22

        var body: some View {
            if row.isSubtransaction {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RegisterCardDetail(register: register, row: row, glyphWidth: glyphWidth)
                    Spacer(minLength: 8)
                    RegisterAmountText(row: row)
                }
                .font(.subheadline)
                .padding(.leading, glyphWidth + RegisterCardDetail.spacing)
                .padding(.trailing, RegisterStatusButton.width + 8)
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: RegisterCardDetail.spacing) {
                            RegisterGlyph(width: glyphWidth) { EmptyView() }
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(verbatim: row.payee).lineLimit(1)
                                if row.hasTransferIcon {
                                    Image(systemName: StatusSymbol.transfer.name)
                                        .font(.footnote)
                                        .foregroundStyle(ThemeColor.secondaryText)
                                        .accessibilityLabel(StatusSymbol.transfer.label)
                                }
                            }
                            Spacer(minLength: 8)
                            RegisterAmountText(row: row)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            RegisterCardDetail(register: register, row: row, glyphWidth: glyphWidth)
                            Spacer(minLength: 8)
                            Text(verbatim: details)
                                .monospacedDigit()
                                .foregroundStyle(ThemeColor.secondaryText)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                        .font(.subheadline)
                    }
                    RegisterStatusButton(register: register, row: row)
                }
            }
        }

        private var details: String {
            register.isAllAccounts ? "\(row.account) · \(row.date)" : row.date
        }
    }

    private struct RegisterGlyph<Content: View>: View {
        let width: CGFloat
        @ViewBuilder let content: Content

        var body: some View {
            ZStack(alignment: .leading) {
                Text(verbatim: " ").accessibilityHidden(true)
                content
            }
            .frame(width: width, alignment: .leading)
        }
    }

    struct RegisterCardDetail: View {
        static let spacing: CGFloat = 6
        static let transferTitle = "Umbuchung"

        let register: RegisterViewModel
        let row: RegisterRow
        let glyphWidth: CGFloat

        var body: some View {
            if row.split == .none {
                line
            } else {
                Button {
                    register.toggleSplit(row.transactionId)
                } label: {
                    line
                }
                .buttonStyle(.borderless)
                .tint(ThemeColor.secondaryText)
                .accessibilityHint(row.split == .expanded ? "Teile ausblenden" : "Teile zeigen")
            }
        }

        private var line: some View {
            HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
                RegisterGlyph(width: glyphWidth) { glyph }
                HStack(spacing: 4) {
                    if !name.isEmpty {
                        Text(verbatim: name).foregroundStyle(nameColor).layoutPriority(1)
                    }
                    if !row.memo.isEmpty {
                        if !name.isEmpty {
                            Text(verbatim: "·").foregroundStyle(ThemeColor.secondaryText).accessibilityHidden(true)
                        }
                        Text(verbatim: row.memo).foregroundStyle(ThemeColor.secondaryText)
                    }
                }
                .lineLimit(1)
            }
        }

        @ViewBuilder
        private var glyph: some View {
            if row.split != .none {
                Image(systemName: row.split == .expanded ? "square.split.2x1.fill" : "square.split.2x1")
                    .foregroundStyle(ThemeColor.secondaryText)
                    .accessibilityHidden(true)
            } else if row.isSubtransaction && row.hasTransferIcon {
                Image(systemName: StatusSymbol.transfer.name)
                    .foregroundStyle(ThemeColor.secondaryText)
                    .accessibilityLabel(StatusSymbol.transfer.label)
            } else if row.categoryStyle == .needsCategory {
                Image(systemName: StatusSymbol.warning)
                    .foregroundStyle(ThemeColor.warning)
                    .accessibilityHidden(true)
            } else if let emoji = row.category.leadingEmoji?.emoji {
                Text(verbatim: emoji).accessibilityHidden(true)
            }
        }

        private var name: String {
            if row.category.isEmpty { return row.hasTransferIcon && row.memo.isEmpty ? Self.transferTitle : "" }
            return row.category.leadingEmoji?.name ?? row.category
        }

        private var nameColor: Color {
            switch row.categoryStyle {
            case .needsCategory: ThemeColor.warning
            case .error: ThemeColor.negative
            case .plain, .bold: ThemeColor.secondaryText
            }
        }
    }

    /// The cells keep the table's widths, so the header and every row line up.
    struct RegisterColumnsLayout: Layout {
        let table: RegisterTouchTable

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let width = proposal.width ?? 600
            let heights = zip(subviews, table.widths(in: width)).map { subview, width in
                subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            }
            return CGSize(width: width, height: heights.max() ?? 0)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            var x = bounds.minX
            for (subview, width) in zip(subviews, table.widths(in: bounds.width)) {
                subview.place(
                    at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                    proposal: ProposedViewSize(width: width, height: bounds.height))
                x += width + RegisterTouchTable.spacing
            }
        }
    }

    private struct RegisterTableCell<Content: View>: View {
        let column: RegisterColumn
        @ViewBuilder let content: Content

        var body: some View {
            content.frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
        }

        private var alignment: Alignment {
            if column == .cleared { return .center }
            return column.isAmount ? .trailing : .leading
        }
    }

    struct RegisterColumnHeader: View {
        let table: RegisterTouchTable

        var body: some View {
            RegisterColumnsLayout(table: table) {
                ForEach(table.columns, id: \.self) { column in
                    RegisterTableCell(column: column) {
                        switch column.header {
                        case .text(let title): Text(verbatim: title)
                        case .symbol(let name, let label): Image(systemName: name).accessibilityLabel(label)
                        }
                    }
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(ThemeColor.secondaryText)
            .lineLimit(1)
        }
    }

    struct RegisterTableRow: View {
        let register: RegisterViewModel
        let row: RegisterRow
        let table: RegisterTouchTable

        var body: some View {
            RegisterColumnsLayout(table: table) {
                ForEach(table.columns, id: \.self) { column in
                    RegisterTableCell(column: column) { cell(column) }
                }
            }
            .font(.subheadline)
            .lineLimit(1)
        }

        @ViewBuilder
        private func cell(_ column: RegisterColumn) -> some View {
            switch column {
            case .account: Text(verbatim: row.account)
            case .date: Text(verbatim: row.date).monospacedDigit()
            case .payee: RegisterPayeeText(row: row).truncationMode(.middle)
            case .category: RegisterCategoryText(register: register, row: row)
            case .memo: Text(verbatim: row.memo).foregroundStyle(ThemeColor.secondaryText)
            case .amount: RegisterAmountText(row: row)
            case .cleared:
                if !row.isSubtransaction { RegisterStatusButton(register: register, row: row) }
            case .repeats: EmptyView()
            }
        }
    }

    struct RegisterPayeeText: View {
        let row: RegisterRow

        var body: some View {
            HStack(spacing: 4) {
                if row.hasTransferIcon {
                    Image(systemName: StatusSymbol.transfer.name)
                        .foregroundStyle(ThemeColor.secondaryText)
                        .accessibilityLabel(StatusSymbol.transfer.label)
                }
                Text(verbatim: row.payee).lineLimit(1)
            }
        }
    }

    struct RegisterCategoryText: View {
        let register: RegisterViewModel
        let row: RegisterRow

        var body: some View {
            if row.split == .none {
                label
            } else {
                Button {
                    register.toggleSplit(row.transactionId)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: row.split == .expanded ? "square.split.2x1.fill" : "square.split.2x1")
                            .accessibilityHidden(true)
                        label
                    }
                }
                .buttonStyle(.borderless)
                .tint(color)
                .accessibilityHint(row.split == .expanded ? "Teile ausblenden" : "Teile zeigen")
            }
        }

        private var label: some View {
            HStack(spacing: 4) {
                if row.categoryStyle == .needsCategory {
                    Image(systemName: StatusSymbol.warning).accessibilityHidden(true)
                }
                Text(verbatim: row.category).lineLimit(1)
            }
            .foregroundStyle(color)
        }

        private var color: Color {
            switch row.categoryStyle {
            case .plain, .bold: ThemeColor.text
            case .needsCategory: ThemeColor.warning
            case .error: ThemeColor.negative
            }
        }
    }

    struct RegisterAmountText: View {
        let row: RegisterRow

        var body: some View {
            Text(verbatim: row.amountText)
                .monospacedDigit()
                .fontWeight(row.isSubtransaction ? nil : .medium)
                .foregroundStyle(row.isInflow ? ThemeColor.positive : ThemeColor.text)
                .lineLimit(1)
        }
    }

    /// Colour only where an action waits: the ✓ of a transaction to approve.
    struct RegisterStatusButton: View {
        static let width: CGFloat = 28

        let register: RegisterViewModel
        let row: RegisterRow

        var body: some View {
            let action = register.statusAction(for: row)
            let image =
                glyph
                .frame(width: Self.width, height: Self.width)
                .accessibilityLabel(label)
            if !register.isPicking {
                Button {
                    register.statusTapped(row)
                } label: {
                    image.frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityHint(action.title)
            } else {
                image
            }
        }

        @ViewBuilder
        private var glyph: some View {
            if row.errorLevel == .forReview {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(ThemeColor.accent)
            } else {
                Image(systemName: symbolName)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ThemeColor.secondaryText)
            }
        }

        private var symbolName: String {
            switch row.cleared {
            case .uncleared: "circle"
            case .cleared: "checkmark"
            case .reconciled: "lock.fill"
            }
        }

        private var label: String {
            row.errorLevel == .forReview ? "Zu bestätigen" : row.cleared.symbol.label
        }
    }
#endif

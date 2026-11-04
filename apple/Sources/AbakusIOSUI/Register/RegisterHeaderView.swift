#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct RegisterHeaderView: View {
        let register: RegisterViewModel
        let table: RegisterTouchTable?
        /// How far "Auswählen"'s selection circles push the table's cells past the rows' inset.
        var columnIndent: CGFloat = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                RegisterBalances(register: register, summary: register.summary, isLarge: table != nil)
                if register.isShowingApprovals {
                    approvalsLine
                } else if register.account != nil && !register.isReconciling {
                    reconcileLine
                }
                let notifiers = shownNotifiers
                if !notifiers.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(notifiers) { notifier in
                                RegisterNotifierChip(notifier: notifier) { chipTapped(notifier.kind) }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
                if let footer = register.reconciliation.footer {
                    infoLine(
                        "\(register.transactionIds.count) Buchungen bis \(footer.statementDate)",
                        clearTitle: register.search.info?.clearButtonTitle)
                } else if !register.isShowingApprovals, let info = register.search.info {
                    infoLine(RegisterSearchController.touchText(info.message), clearTitle: info.clearButtonTitle)
                }
                if let table {
                    RegisterColumnHeader(table: table)
                        .padding(.leading, columnIndent)
                        .padding(.top, 2)
                }
            }
            .padding(.leading, RegisterList.rowInsets.leading)
            .padding(.trailing, RegisterList.rowInsets.trailing)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(ThemeColor.contentBackground.ignoresSafeArea(edges: .top))
        }

        /// A chip leads to a search of its own, so while another search filters the list only Undo stays.
        private var shownNotifiers: [RegisterNotifier] {
            let list = register.notifiers.list
            return register.search.isFiltered ? list.filter { $0.kind == .undo } : list
        }

        private var reconcileLine: some View {
            HStack(spacing: 12) {
                Text(verbatim: register.reconciledLabel ?? "Noch nicht abgeglichen")
                    .font(.footnote)
                    .foregroundStyle(ThemeColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if register.reconciliation.isReconcileEnabled {
                    ProminentButton(title: "Abgleichen", action: register.reconciliation.reconcileClicked)
                }
            }
        }

        @ViewBuilder
        private var approvalsLine: some View {
            if let line = register.approvalsLine {
                HStack(spacing: 12) {
                    Text(verbatim: line)
                        .font(.footnote)
                        .foregroundStyle(ThemeColor.secondaryText)
                    Spacer(minLength: 8)
                    ProminentButton(title: "Alle bestätigen", action: register.approveAllClicked)
                }
            }
        }

        private func infoLine(_ message: String, clearTitle: String?) -> some View {
            HStack(spacing: 8) {
                Text(verbatim: message)
                    .foregroundStyle(ThemeColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let clearTitle {
                    Button(clearTitle, action: register.search.clearClicked)
                        .fixedSize()
                }
            }
            .font(.footnote)
        }

        private func chipTapped(_ kind: RegisterNotifier.Kind) {
            if kind == .reminder {
                register.showApprovals()
            } else {
                register.notifiers.clicked(kind)
            }
        }
    }

    /// The dark label keeps 4.5:1 on dark mode's light accent.
    struct ProminentButton: View {
        let title: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundStyle(ThemeColor.selectedText)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(ThemeColor.accent)
            .fixedSize()
        }
    }

    /// A search puts its total in the place of Gebucht and Vorgemerkt.
    struct RegisterBalances: View {
        let register: RegisterViewModel
        let summary: RegisterSummary
        let isLarge: Bool

        var body: some View {
            RegisterEquationLayout(spacing: isLarge ? 12 : 6) {
                item(summary.first)
                if summary.showsOperands { operand("+") }
                item(summary.second)
                if summary.showsOperands {
                    operand("=")
                } else {
                    Color.clear.frame(width: isLarge ? 12 : 10, height: 0)
                }
                item(summary.working)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }

        @ViewBuilder
        private func item(_ item: RegisterSummaryItem) -> some View {
            if item.kind != .blank {
                let title = Text(verbatim: item.title)
                    .font(.caption)
                    .foregroundStyle(ThemeColor.secondaryText)
                let amount = Text(verbatim: item.amountText)
                    .font((isLarge ? Font.title3 : .subheadline).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.isNegative ? ThemeColor.negative : ThemeColor.text)
                if item.isClickable {
                    Button {
                        register.summaryClicked(item.kind)
                    } label: {
                        title
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                    .layoutValue(key: RegisterEquationRole.self, value: .title)
                    Button {
                        register.summaryClicked(item.kind)
                    } label: {
                        amount
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.title) \(item.amountText)")
                    .accessibilityHint(item.tooltip ?? "")
                    .layoutValue(key: RegisterEquationRole.self, value: .amount)
                } else {
                    title
                        .accessibilityHidden(true)
                        .layoutValue(key: RegisterEquationRole.self, value: .title)
                    amount
                        .accessibilityLabel("\(item.title) \(item.amountText)")
                        .layoutValue(key: RegisterEquationRole.self, value: .amount)
                }
            }
        }

        private func operand(_ symbol: String) -> some View {
            Text(verbatim: symbol)
                .font(isLarge ? .title3 : .subheadline)
                .foregroundStyle(ThemeColor.secondaryText)
                .accessibilityHidden(true)
        }
    }

    private enum RegisterEquationRole: LayoutValueKey {
        case title, amount, operand

        static let defaultValue = Self.operand
    }

    /// The amounts and operators keep one spacing however wide the titles above them are.
    private struct RegisterEquationLayout: Layout {
        static let titleSpacing: CGFloat = 1
        static let titleGap: CGFloat = 10

        let spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let frames = frames(subviews, width: proposal.width)
            return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            for (subview, frame) in zip(subviews, frames(subviews, width: bounds.width)) {
                subview.place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    proposal: ProposedViewSize(frame.size))
            }
        }

        /// Too wide for the screen, every part gets its share of the width, which its text's scale factor fits.
        private func frames(_ subviews: Subviews, width: CGFloat?) -> [CGRect] {
            let natural = frames(subviews, scale: 1)
            let used = natural.map(\.maxX).max() ?? 0
            guard let width, used > width, used > 0 else { return natural }
            return frames(subviews, scale: width / used)
        }

        private func frames(_ subviews: Subviews, scale: CGFloat) -> [CGRect] {
            let dimensions = subviews.map { subview in
                let ideal = subview.sizeThatFits(.unspecified)
                return subview.dimensions(in: ProposedViewSize(width: ideal.width * scale, height: nil))
            }
            let roles = subviews.map { $0[RegisterEquationRole.self] }
            let amountY =
                (zip(roles, dimensions).filter { $0.0 == .title }.map(\.1.height).max() ?? 0) + Self.titleSpacing
            let baseline = zip(roles, dimensions).first { $0.0 == .amount }.map { amountY + $0.1[.lastTextBaseline] }
            var frames = [CGRect](repeating: .zero, count: subviews.count)
            var x: CGFloat = 0
            var titleEnd: CGFloat = 0
            var title: Int?
            for index in subviews.indices {
                let size = CGSize(width: dimensions[index].width, height: dimensions[index].height)
                switch roles[index] {
                case .title:
                    title = index
                case .amount:
                    let column = max(x, titleEnd)
                    if let title {
                        frames[title] = CGRect(
                            x: column, y: 0, width: dimensions[title].width, height: dimensions[title].height)
                        titleEnd = column + dimensions[title].width + Self.titleGap
                    }
                    title = nil
                    frames[index] = CGRect(origin: CGPoint(x: column, y: amountY), size: size)
                    x = column + size.width
                case .operand:
                    x += spacing
                    let y = (baseline ?? amountY) - dimensions[index][.lastTextBaseline]
                    frames[index] = CGRect(origin: CGPoint(x: x, y: y), size: size)
                    x += size.width + spacing
                }
            }
            return frames
        }
    }

    struct RegisterNotifierChip: View {
        let notifier: RegisterNotifier
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(verbatim: notifier.text)
                    if let link = notifier.link { Text(verbatim: link).fontWeight(.semibold) }
                }
                .font(.footnote.weight(.medium))
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(tint)
            .accessibilityHint(notifier.tooltip ?? "")
        }

        private var tint: Color {
            switch notifier.kind {
            case .error: ThemeColor.negative
            case .warning: ThemeColor.warning
            case .reminder: ThemeColor.accent
            case .undo: ThemeColor.secondaryText
            }
        }
    }

    struct TimeframeSheet: View {
        let search: RegisterSearchController

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        ForEach(DateFilterPreset.allCases, id: \.self) { preset in
                            Button {
                                search.timeframePresetClicked(preset)
                            } label: {
                                HStack {
                                    Text(preset.label).foregroundStyle(ThemeColor.text)
                                    Spacer()
                                    if search.timeframePreset == preset {
                                        Image(systemName: "checkmark").foregroundStyle(ThemeColor.accent)
                                    }
                                }
                            }
                            .disabled(!search.isTimeframePresetEnabled(preset))
                        }
                    }
                    Section("Eigener Zeitraum") {
                        monthRow("Von", start: true)
                        monthRow("Bis", start: false)
                    }
                }
                .navigationTitle("Zeitraum")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen", systemImage: "xmark", role: .close, action: search.timeframeCancelled)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig", systemImage: "checkmark", role: .confirm, action: search.timeframeDone)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(ThemeColor.groupedBackground)
            .presentationDragIndicator(.visible)
        }

        private func monthRow(_ label: String, start: Bool) -> some View {
            LabeledContent(label) {
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
                        ForEach(search.timeframeYears, id: \.self) { year in
                            Text(verbatim: String(year)).tag(year)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }
#endif

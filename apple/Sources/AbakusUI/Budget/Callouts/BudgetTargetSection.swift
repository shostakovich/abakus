import AbakusCore
import SwiftUI

/// The category callout's "Ziel": the target in the callout's month, its editor, or how to set one.
struct BudgetTargetSection: View {
    static let labelWidth: CGFloat = 80

    let controller: BudgetCalloutController
    let form: BudgetCategoryForm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Ziel").font(ThemeFont.headline.font).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(verbatim: controller.targetMonthTitle).foregroundStyle(ThemeColor.secondaryText)
            }
            if let editor = form.target {
                BudgetTargetEditor(controller: controller, editor: editor, month: form.month)
            } else if let display = controller.targetDisplay {
                BudgetTargetView(controller: controller, display: display)
            } else {
                Text(verbatim: BudgetCalloutController.noTargetText)
                    .foregroundStyle(ThemeColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: controller.editTargetClicked) { Label("Ziel festlegen", systemImage: "target") }
            }
        }
    }
}

private struct BudgetTargetView: View {
    let controller: BudgetCalloutController
    let display: BudgetTargetDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: display.head).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                status
                Spacer(minLength: 0)
                if let label = display.assignLabel {
                    Button("Zuweisen", action: controller.assignTargetClicked).accessibilityLabel(label)
                }
            }
            if let progress = display.progress { BudgetTargetBar(progress: progress) }
            HStack(spacing: 8) {
                Button(action: controller.snoozeClicked) {
                    Label(display.snoozeTitle, systemImage: display.isSnoozed ? "play" : "pause")
                }
                Button(action: controller.editTargetClicked) { Label("Ziel bearbeiten", systemImage: "pencil") }
            }
        }
    }

    private var status: some View {
        let symbol = display.status.state.symbol
        return HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol.name).foregroundStyle(symbol.color).accessibilityHidden(true)
            }
            Text(verbatim: display.status.text).foregroundStyle(display.status.state.textColor)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BudgetTargetBar: View {
    static let height: CGFloat = 6
    static let markHeight: CGFloat = 12

    let progress: BudgetTargetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(verbatim: progress.label).monospacedDigit()
                Spacer(minLength: 0)
                Text(verbatim: progress.percentText).monospacedDigit().foregroundStyle(ThemeColor.secondaryText)
            }
            .font(ThemeFont.caption.font)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(ThemeColor.groupFill)
                    Capsule().fill(ThemeColor.accent).frame(width: width * progress.value)
                    if let mark = progress.mark {
                        Capsule()
                            .fill(ThemeColor.text)
                            .frame(width: 2, height: Self.markHeight)
                            .offset(x: min(max(width * mark - 1, 0), width - 2))
                    }
                }
                .frame(height: Self.height)
                .frame(maxHeight: .infinity)
            }
            .frame(height: Self.markHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.label)
        .accessibilityValue(progress.percentText)
    }
}

private struct BudgetTargetEditor: View {
    let controller: BudgetCalloutController
    let editor: BudgetTargetForm
    let month: DateWithoutTime
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        @Bindable var controller = controller
        let formatter = controller.formatter
        let calendar = formatter.dateLocale.calendar
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    label("Ich brauche")
                    amount
                }
                GridRow {
                    label("Rhythmus")
                    Picker("Rhythmus", selection: $controller.targetCadence) {
                        ForEach(BudgetTargetCadence.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if editor.cadence == .byDate {
                    GridRow {
                        label("Fällig am")
                        HStack(spacing: 8) {
                            DatePicker(
                                "Fällig am",
                                selection: Binding(
                                    get: { controller.targetDueOn.date(in: calendar) },
                                    set: { controller.targetDueOn = DateWithoutTime($0, in: calendar) }),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .environment(\.locale, Locale(identifier: formatter.dateLocale.identifier))
                            CalendarPopoverButton(date: $controller.targetDueOn, locale: formatter.dateLocale)
                            Toggle("Jährlich wiederholen", isOn: $controller.targetRepeatsYearly).fixedSize()
                        }
                    }
                }
                GridRow {
                    HStack(spacing: 8) {
                        Text("Nächsten Monat möchte ich:").fixedSize()
                        Picker("Nächsten Monat möchte ich:", selection: $controller.targetKind) {
                            ForEach(BudgetTargetKind.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .gridCellColumns(2)
                }
            }
            if let error = editor.error {
                Text(verbatim: error)
                    .foregroundStyle(ThemeColor.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if !editor.isNew {
                    Button(role: .destructive, action: controller.deleteTargetClicked) {
                        Label("Ziel löschen", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(ThemeColor.negative)
                    .fixedSize()
                }
                Spacer(minLength: 0)
                Button("Abbrechen", action: controller.targetCancelClicked)
                Button("Speichern", action: controller.targetSaveClicked).buttonStyle(.borderedProminent)
            }
        }
        .onAppear { isAmountFocused = true }
        .onChange(of: editor.focusRequest) { isAmountFocused = true }
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .frame(width: BudgetTargetSection.labelWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .gridColumnAlignment(.leading)
    }

    private var amount: some View {
        @Bindable var controller = controller
        return BudgetAmountField(
            label: "Ich brauche", text: $controller.targetAmount, locale: controller.formatter.currencyLocale,
            isFocused: $isAmountFocused
        )
        .onSubmit(controller.targetSaveClicked)
    }
}

extension BudgetTargetState {
    var symbol: StatusSymbol? {
        switch self {
        case .overspent: nil
        case .snoozed: StatusSymbol(name: "pause.circle.fill", color: ThemeColor.secondaryText, label: "Pausiert")
        case .underfunded: BudgetAvailableMarker.underfunded.symbol
        case .onTrack, .met: BudgetAvailableMarker.funded.symbol
        }
    }

    var textColor: Color {
        switch self {
        case .overspent: ThemeColor.negative
        case .snoozed: ThemeColor.secondaryText
        case .underfunded: ThemeColor.warning
        case .onTrack, .met: ThemeColor.positive
        }
    }
}

extension BudgetAvailableMarker {
    var symbol: StatusSymbol {
        switch self {
        case .underfunded: StatusSymbol(name: "clock.fill", color: ThemeColor.warning, label: label)
        case .funded: StatusSymbol(name: "checkmark.circle.fill", color: ThemeColor.positive, label: label)
        case .snoozed: StatusSymbol(name: "pause.circle.fill", color: ThemeColor.secondaryText, label: label)
        }
    }
}

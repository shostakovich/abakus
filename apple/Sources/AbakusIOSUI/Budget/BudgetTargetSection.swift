#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct BudgetTargetSection: View {
        let controller: BudgetCalloutController
        let form: BudgetCategoryForm
        var focus: FocusState<BudgetSheetField?>.Binding

        var body: some View {
            Section("Ziel") {
                if let editor = form.target {
                    BudgetTargetEditor(controller: controller, editor: editor, focus: focus)
                } else if let display = controller.targetDisplay {
                    BudgetTargetCard(controller: controller, display: display)
                    Button("Ziel bearbeiten", systemImage: "pencil", action: controller.editTargetClicked)
                    Button(
                        display.snoozeTitle, systemImage: display.isSnoozed ? "play" : "pause",
                        action: controller.snoozeClicked)
                } else {
                    Text(verbatim: BudgetCalloutController.noTargetText).foregroundStyle(ThemeColor.secondaryText)
                    Button("Ziel festlegen", systemImage: "target", action: controller.editTargetClicked)
                }
            }
        }
    }

    private struct BudgetTargetCard: View {
        private static let padding: CGFloat = 12

        let controller: BudgetCalloutController
        let display: BudgetTargetDisplay

        var body: some View {
            let state = display.status.state
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: display.head).font(.subheadline.weight(.semibold)).foregroundStyle(ThemeColor.text)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let symbol = state.symbol {
                        Image(systemName: symbol.name).foregroundStyle(symbol.color).accessibilityHidden(true)
                    } else if state == .overspent {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(ThemeColor.negative)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: display.status.text).foregroundStyle(ThemeColor.text)
                }
                .font(.subheadline)
                if let progress = display.progress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress.value).tint(state.textColor)
                        HStack {
                            Text(verbatim: progress.label)
                            Spacer(minLength: 8)
                            Text(verbatim: progress.percentText)
                        }
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(ThemeColor.secondaryText)
                    }
                }
                if let label = display.assignLabel {
                    ProminentButton(title: label, action: controller.assignTargetClicked)
                        .padding(.top, 2)
                }
            }
            .padding(Self.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(state.textColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    private struct BudgetTargetEditor: View {
        let controller: BudgetCalloutController
        let editor: BudgetTargetForm
        var focus: FocusState<BudgetSheetField?>.Binding

        var body: some View {
            @Bindable var controller = controller
            let calendar = controller.formatter.dateLocale.calendar
            BudgetAmountField(label: "Ich brauche", text: $controller.targetAmount, focus: focus, field: .target)
                .onAppear { focus.wrappedValue = .target }
                .onChange(of: editor.focusRequest) { focus.wrappedValue = .target }
            Picker("Rhythmus", selection: $controller.targetCadence) {
                ForEach(BudgetTargetCadence.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if editor.cadence == .byDate {
                DatePicker(
                    "Fällig am",
                    selection: Binding(
                        get: { controller.targetDueOn.date(in: calendar) },
                        set: { controller.targetDueOn = DateWithoutTime($0, in: calendar) }),
                    displayedComponents: .date
                )
                .environment(\.locale, calendar.locale ?? .current)
                .environment(\.calendar, calendar)
                Toggle("Jährlich wiederholen", isOn: $controller.targetRepeatsYearly)
            }
            Picker("Nächsten Monat möchte ich:", selection: $controller.targetKind) {
                ForEach(BudgetTargetKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if let error = editor.error {
                Text(verbatim: error).foregroundStyle(ThemeColor.negative)
            }
            Button("Ziel speichern", systemImage: "checkmark", action: controller.targetSaveClicked)
            Button("Abbrechen", action: controller.targetCancelClicked)
            if !editor.isNew {
                Button("Ziel löschen", systemImage: "trash", role: .destructive, action: controller.deleteTargetClicked)
                    .foregroundStyle(ThemeColor.negative)
            }
        }
    }
#endif

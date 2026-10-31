import AbakusCore
import SwiftUI

/// A sheet with a grouped form: Return answers the confirm button, Escape the Cancel button.
struct FormSheet<Content: View>: View {
    static var width: CGFloat { 500 }
    static var fieldWidth: CGFloat { 220 }

    let title: String
    var message: Text?
    let confirmTitle: String
    var canConfirm = true
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                if let message {
                    message.foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            Form { content }
                .formStyle(.grouped)
                .scrollDisabled(true)
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("Abbrechen", action: onCancel).keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm).keyboardShortcut(.defaultAction).disabled(!canConfirm)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: Self.width)
        .interactiveDismissDisabled()
    }
}

/// A labelled row whose control and footnotes share one width across the form.
struct FormSheetRow<Control: View, Footnote: View>: View {
    let label: String
    @ViewBuilder let control: Control
    @ViewBuilder let footnote: Footnote

    var body: some View {
        LabeledContent {
            VStack(alignment: .leading, spacing: 6) {
                control
                footnote
            }
            .frame(width: FormSheet<EmptyView>.fieldWidth, alignment: .leading)
        } label: {
            Text(label)
        }
    }
}

extension FormSheetRow where Footnote == EmptyView {
    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.init(label: label, control: control, footnote: { EmptyView() })
    }
}

extension FormSheetRow {
    init(_ label: String, @ViewBuilder control: () -> Control, @ViewBuilder footnote: () -> Footnote) {
        self.init(label: label, control: control, footnote: footnote)
    }
}

extension Text {
    func formFootnote() -> some View {
        font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The calendar button beside a date: a graphical date picker in a popover.
struct CalendarPopoverButton: View {
    @Binding var date: DateWithoutTime
    let locale: FormatLocale
    @State private var isOpen = false

    var body: some View {
        let calendar = locale.calendar
        Button {
            isOpen.toggle()
        } label: {
            Image(systemName: "calendar").accessibilityLabel("Datum wählen")
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            DatePicker(
                "",
                selection: Binding(get: { date.date(in: calendar) }, set: { date = DateWithoutTime($0, in: calendar) }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.locale, calendar.locale ?? .current)
            .environment(\.calendar, calendar)
            .padding(12)
        }
    }
}

extension FormatLocale {
    /// Gregorian like the budget's dates, with the date locale's first weekday.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: identifier)
        calendar.firstWeekday = firstDayOfWeek + 1
        return calendar
    }
}

extension DateWithoutTime {
    init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}

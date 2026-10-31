import AppKit
import SwiftUI

/// A task dialog with command links: each link is a large button with its detail under the title.
struct CommandLinkSheet: View {
    typealias Dialog = TaskDialog<AnyDialogChoice>

    let dialog: Dialog
    let onAnswer: @MainActor (AnyDialogChoice, Bool) -> Void
    @State private var isChecked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    if !dialog.instruction.isEmpty {
                        Text(TextMarkup.attributed(dialog.instruction)).font(.headline)
                    }
                    if !dialog.content.isEmpty {
                        Text(TextMarkup.attributed(dialog.content))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                ForEach(dialog.commandLinks, id: \.choice) { link in
                    commandLink(link)
                }
            }
            HStack(spacing: 12) {
                if let checkbox = dialog.checkbox {
                    Toggle(checkbox, isOn: $isChecked).toggleStyle(.checkbox)
                }
                Spacer(minLength: 0)
                ForEach(dialog.buttons, id: \.choice) { button in
                    Button(button.title) { answer(button.choice) }
                        .keyboardShortcut(shortcut(for: button.choice, isDefault: button.isDefault))
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .onExitCommand { answer(dialog.dismissal) }
    }

    private func commandLink(_ link: Dialog.CommandLink) -> some View {
        let button = Button {
            answer(link.choice)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(TextMarkup.attributed(link.title)).font(.headline)
                Text(TextMarkup.attributed(link.detail)).font(.callout).opacity(0.8)
            }
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .keyboardShortcut(shortcut(for: link.choice, isDefault: link.isDefault))
        return Group {
            if link.isDefault {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
    }

    private func shortcut(for choice: AnyDialogChoice, isDefault: Bool) -> KeyboardShortcut? {
        if isDefault { return .defaultAction }
        return choice == dialog.dismissal ? .cancelAction : nil
    }

    private func answer(_ choice: AnyDialogChoice) {
        onAnswer(choice, isChecked)
    }
}

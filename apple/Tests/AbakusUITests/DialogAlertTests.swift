import AbakusCore
import AppKit
import Testing

@testable import AbakusUI

private enum Pick: Hashable, Sendable {
    case delete, cancel, fix, correct, other
}

@MainActor
@Suite struct DialogAlertTests {
    private func alert(_ dialog: TaskDialog<Pick>) -> DialogAlert {
        DialogAlert(dialog.map(AnyDialogChoice.init))
    }

    @Test func theDefaultButtonIsTrailingAndCancelLeading() {
        let alert = alert(
            TaskDialog(
                instruction: "Delete 1 transaction?", content: "",
                buttons: [
                    .init(.cancel, title: "Cancel"), .init(.delete, title: "Delete Transaction", isDefault: true),
                ],
                dismissal: .cancel))
        #expect(alert.alert.buttons.map(\.title) == ["Delete Transaction", "Cancel"])
        #expect(alert.alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1B}"])
        #expect(alert.choice(for: .alertFirstButtonReturn) == AnyDialogChoice(Pick.delete))
        #expect(alert.choice(for: .alertSecondButtonReturn) == AnyDialogChoice(Pick.cancel))
        #expect(!alert.escapesWithoutButton)
    }

    @Test func otherButtonsSitBetweenTheDefaultAndCancel() {
        let alert = alert(
            TaskDialog(
                instruction: "q", content: "",
                buttons: [
                    .init(.cancel, title: "Cancel"), .init(.other, title: "Other"),
                    .init(.delete, title: "Delete", isDefault: true),
                ],
                dismissal: .cancel))
        #expect(alert.alert.buttons.map(\.title) == ["Delete", "Other", "Cancel"])
        #expect(alert.alert.buttons.map(\.keyEquivalent) == ["\r", "", "\u{1B}"])
    }

    @Test func escapeAnswersTheDismissalWhenItIsTheDefault() {
        let alert = alert(
            TaskDialog(
                instruction: "Soll der Saldo negativ sein?", content: "",
                buttons: [.init(.fix, title: "Let me fix that", isDefault: true), .init(.correct, title: "Correct")],
                dismissal: .fix))
        #expect(alert.alert.buttons.map(\.title) == ["Let me fix that", "Correct"])
        #expect(alert.alert.buttons.map(\.keyEquivalent) == ["\r", ""])
        #expect(alert.escapesWithoutButton)
        #expect(alert.choice(for: .cancel) == AnyDialogChoice(Pick.fix))
    }

    @Test func aDialogWithoutDefaultLeavesReturnUnassigned() {
        let alert = alert(
            TaskDialog(
                instruction: "q", content: "", buttons: [.init(.other, title: "Other")],
                dismissal: .cancel))
        #expect(alert.alert.buttons.map(\.keyEquivalent) == [""])
    }

    @Test func theAlertShowsTheAppIconAndPlainText() {
        let alert = alert(
            TaskDialog(
                title: "Fehler", instruction: "Das Budget ließ sich nicht sichern.",
                content: "Something is preventing <b>Abakus</b> from saving.<br/><br/>disk full",
                buttons: [.init(.cancel, title: "Close", isDefault: true)], dismissal: .cancel))
        #expect(alert.alert.icon === NSApplication.shared.applicationIconImage)
        #expect(alert.alert.messageText == "Das Budget ließ sich nicht sichern.")
        #expect(alert.alert.informativeText == "Something is preventing Abakus from saving.\n\ndisk full")
        #expect(!alert.alert.showsSuppressionButton)
    }

    @Test func theCheckboxBecomesTheSuppressionToggle() {
        let alert = alert(
            TaskDialog(
                instruction: "q", content: "", buttons: [.init(.cancel, title: "Cancel")],
                checkbox: "Don't ask again", dismissal: .cancel))
        #expect(alert.alert.showsSuppressionButton)
        #expect(alert.alert.suppressionButton?.title == "Don't ask again")
        #expect(!alert.isSuppressed)
        alert.alert.suppressionButton?.state = .on
        #expect(alert.isSuppressed)
    }
}

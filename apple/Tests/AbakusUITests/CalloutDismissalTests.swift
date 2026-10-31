import AppKit
import Testing

@testable import AbakusUI

@MainActor
@Suite struct CalloutDismissalTests {
    private func key(_ code: UInt16, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private var click: NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @Test func escapeClosesACalloutThatHasNoFocus() {
        let escape = key(53, "\u{1B}")
        #expect(
            CalloutDismissal.response(to: escape, isHovered: false, closesOnClickOutside: false) == .dismissAndConsume)
        #expect(CalloutDismissal.response(to: key(0, "a"), isHovered: false, closesOnClickOutside: false) == .ignore)
        #expect(CalloutDismissal.response(to: click, isHovered: false, closesOnClickOutside: false) == .ignore)
    }

    @Test func aClickOutsideClosesAndStillGoesThrough() {
        #expect(CalloutDismissal.response(to: click, isHovered: false, closesOnClickOutside: true) == .dismiss)
        #expect(CalloutDismissal.response(to: click, isHovered: true, closesOnClickOutside: true) == .ignore)
    }
}

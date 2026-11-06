import AbakusCore
import AppKit
import Foundation
import Testing

@testable import AbakusMacUI
@testable import AbakusUI
@testable import AbakusUITests

@MainActor
@Suite struct NativeMenuTests {
    private func menu(_ chosen: @escaping (RegisterMenuAction) -> Void) -> (NSMenu, RegisterMenuTarget) {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, cleared: .cleared)
        let model = fixture.model()
        model.rowClicked(model.rows.first { $0.id == id }!, column: nil, modifiers: .command)
        let target = RegisterMenuTarget(perform: chosen)
        return (target.menu(model.contextMenu(for: model.rows.first { $0.id == id }!) ?? []), target)
    }

    @Test func nativeMenuMirrorsTheItems() {
        let (menu, _) = menu { _ in }
        #expect(menu.items.first?.title == "Kategorisieren als")
        #expect(menu.items.first { $0.title == "Löschen" }?.isEnabled == true)
        #expect(
            menu.items.first { $0.title == "In Konto verschieben" }?.submenu?.items.map(\.title) == [
                "Depot", "Karte", "Tagesgeld",
            ])
        #expect(!menu.autoenablesItems)
    }

    @Test func choosingAnItemPerformsItsAction() {
        var chosen: [RegisterMenuAction] = []
        let (menu, target) = menu { chosen.append($0) }
        _ = NSApplication.shared
        let index = menu.indexOfItem(withTitle: "Löschen")
        menu.performActionForItem(at: index)
        #expect(chosen == [.delete])
        _ = target
    }

    @Test func checkedItemsShowTheirState() {
        let model = RegisterFixture().model()
        model.toggleColumnVisibility(.memo)
        let target = RegisterMenuTarget { _ in }
        let menu = target.menu(model.viewMenu)
        #expect(menu.item(withTitle: "Status")?.state == .on)
        #expect(menu.item(withTitle: "Memo")?.state == .off)
    }
}

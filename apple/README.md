# Abakus for the Mac, iPhone and iPad

A native SwiftUI client of the Abakus budget for macOS and iOS (ADR 0029 in [`../DECISIONS.md`](../DECISIONS.md)),
with the budget, the account registers and the payees: on the Mac in one window with a sidebar, on the iPhone and
the iPad in tabs (Budget, Konten, Einstellungen). It follows Abakus's budget rules and speaks German with Abakus's
terms ([`../CONTEXT.md`](../CONTEXT.md)). Commands below run in this folder.

- Targets: `AbakusCore` (model, store, persistence, formatting), `AbakusUI` (view models, theme and the views that
  work on the Mac and iOS, ADR 0031), `AbakusMacUI` (the Mac's screens and everything on AppKit, pointer or keyboard),
  `AbakusIOSUI` (the screens of the iPhone and the iPad), `Abakus` (the Mac app), `Snapshot` (offscreen render and
  event-driven checks), with their tests in `Tests/`.
  `AbakusMacUITests` reuses the fixtures of `AbakusUITests`.

## Setup

- Run the app: `swift run Abakus`. The budget lives in SQLite, `~/Library/Application Support/Abakus/budget.sqlite`,
  with Abakus's synced tables, the message log and its outbox, the field clocks and the sync state (ADR 0027).
  `ABAKUS_DATABASE=<path>` uses another one. A database that cannot be
  opened stops the launch and stays untouched. The first save of each day keeps the database as it was as
  `budget.sqlite.bak`, and `budget.sqlite.lock` keeps a second copy of the app from opening the same budget. A
  `budget.json` of earlier versions is left alone.
- Sync: until it is signed in, the window shows only the sign-in: it takes the address of an Abakus server and signs
  the Mac in through the server's sign-in page (`sync/PROTOCOL.md`); the tokens live in the Keychain under
  `local.abakus.sync`. Signing in loads the server's budget and keeps the database as it was before as
  `budget.sqlite.before-sign-in`; signing out deletes the copy and returns to the sign-in. Einstellungen → Sync and
  the cloud at the bottom of the sidebar show the state.
- Build an app bundle: `tools/make_app.sh` makes a release build and wraps it as `build/Abakus.app` (unsigned,
  for local use). It compiles the app icon, `Sources/Abakus/AppIcon.icon` (an Icon Composer document), with
  Xcode's `actool`; `swift run` shows no icon.
- Render the window offscreen: `swift run Snapshot out.png [--account <name>] [--scale 2] [--select <n>]
  [--expand-splits] [--collapsed-sidebar] [--width 1020] [--height 700] [--dark] [--increase-contrast]`; it renders
  in light mode unless `--dark` or `--increase-contrast` (combinable) ask otherwise. The image is the whole window:
  the toolbar (the screen's title and its items) above content of `--width`×`--height`.
  `--budget <state>` shows the budget screen of the test budget "Business" (today 24.10.2026) in a state (`screen`,
  `edit`, `expanded-header`, `collapsed-all`, `drag`, `hover`, `uncategorized`, `targets` with the Verfügbar markers)
  or with one of its popups open (`month-menu`, `add-master`, `add-sub`, `edit-category`, `edit-master`,
  `rename-error`, `delete-category`, `summary`, `uncategorized-summary`, `account-view`, `cover` with an overspent
  Lernen's cover list, `cover-ready` with Zu verteilen above zero, `undo-notice` after covering, `amount-error` with
  a refused Zugewiesen, `target`, `target-editor`);
  `--month 2023-05` picks the first shown month and `--test-edits` adds the session's later edits (`summary` and
  `account-view` need them).
  `--edit <state>` first types into the register with real key events (`existing`, `new`, `inflow`, `payee-dropdown`,
  `category-dropdown`, `split`, `errors`, `unassigned`, `calendar`, `invalid-payee`, `income-check`,
  `account-field`, `amount-error`); `--trace` prints the editor state afterwards. `--ops <state>` opens register
  operations instead (`context-menu`, `search-active`, `approvals`, `notifiers`, `needs-category`,
  `delete-dialog`); menus, native in the app, are drawn inline.
  `--ops keys` sends real key and mouse events and prints what the register did with them (add `--native-menus` to
  run it with native menus); without a menu bar, menu key equivalents run their Buchungen menu command and ⌘A sends
  Select All's `selectAll:`. `--ui <state>` opens a reconciliation, scheduler, account, payee settings or sign-in
  state through the view models (`rec-statement-dialog`, `rec-footer`, `sched-pane`, `sched-empty`, `sched-edit`,
  `sched-custom` with Eigene, `account-add`, `account-edit`, `account-close`, `closed-accounts`, `closed-account`,
  `kasse` with the Kasse's account, `sign-in`, `payee-settings`, `payee-settings-multi`,
  `payee-settings-empty`, `payee-settings-category`); it runs before `--ops`, so both can be
  combined. Open sheets and alerts are drawn over the window.

## iPhone and iPad

- `iOS/Abakus.xcodeproj` is the iOS app: one source file that hosts `AbakusIOSUI`'s scene, the app icon and the
  settings in `iOS/Abakus.xcconfig`. Copy `iOS/Signing.xcconfig.template` to `iOS/Signing.xcconfig` (git ignores it),
  fill in your own team and a bundle id of your own, open the project in Xcode and run it on the device. The team is
  that of a paid Apple Developer Program membership; a free personal team works too, but it limits the devices and
  its installs run out after seven days, when running the app again from Xcode installs it anew and keeps the budget
  and the sign-in.
- The budget lives in the app's container (`Library/Application Support/Abakus/budget.sqlite`) with the Mac's rules
  for opening, backups and sign-in; the tokens live in the Keychain under the database's path inside the container,
  as the container's own path changes with each install. The app syncs while it is in the foreground, and when it
  becomes active or the network comes back. Abakus lists the device as "iPhone" or "iPad".
- `tools/test_ios.sh` builds the app and runs the core's tests on an iPhone simulator, through the shared scheme
  `AbakusCoreTests` in `.swiftpm/xcode`.

## Gates

- `swift build -Xswiftc -warnings-as-errors`
- `swift test`
- `swift format lint --strict --recursive Package.swift Sources Tests iOS`
- `swift build --scratch-path .build/ios --target AbakusIOSUI --triple arm64-apple-ios26.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -Xswiftc -warnings-as-errors` (the iOS UI on the simulator)
- `tools/test_ios.sh` (the iOS app, and the core's tests on an iPhone simulator)

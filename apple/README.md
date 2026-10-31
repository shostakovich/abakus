# Abakus for the Mac

A native macOS SwiftUI client for the Abakus budget (ADR 0029 in [`../DECISIONS.md`](../DECISIONS.md)), with account
registers and the budget screen (window, sidebar, register, budget). It follows Abakus's budget rules and speaks German
with Abakus's terms ([`../CONTEXT.md`](../CONTEXT.md)). Commands below run in this folder.

- Targets: `AbakusCore` (model, store, persistence, formatting), `AbakusUI` (SwiftUI views and theme),
  `Abakus` (the app), `Snapshot` (offscreen render and event-driven checks), with their tests in `Tests/`.

## Setup

- Run the app: `swift run Abakus`. The budget lives in SQLite, `~/Library/Application Support/Abakus/budget.sqlite`,
  with Abakus's synced tables, the message log and its outbox, the field clocks and the sync state (ADR 0027); an
  empty database gets a fictional demo budget. `ABAKUS_DATABASE=<path>` uses another one. A database that cannot be
  opened stops the launch and stays untouched. The first save of each day keeps the database as it was as
  `budget.sqlite.bak`, and `budget.sqlite.lock` keeps a second copy of the app from opening the same budget. A
  `budget.json` of earlier versions is left alone.
- Sync: Einstellungen → Sync takes the address of an Abakus server and signs the Mac in through its sign-in page
  (`sync/PROTOCOL.md`); the tokens live in the Keychain under `local.abakus.sync`. Signing in replaces the budget
  with the server's and keeps the one before as `budget.sqlite.before-sign-in`; signing out deletes the copy and
  brings back the demo budget. The cloud at the bottom of the sidebar shows the state and opens the settings.
- Build an app bundle: `tools/make_app.sh` makes a release build and wraps it as `build/Abakus.app` (unsigned,
  for local use). It compiles the app icon, `Sources/Abakus/AppIcon.icon` (an Icon Composer document), with
  Xcode's `actool`; `swift run` shows no icon.
- Render the window offscreen: `swift run Snapshot out.png [--account <name>] [--scale 2] [--select <n>]
  [--expand-splits] [--collapsed-sidebar] [--width 1020] [--height 700] [--dark] [--increase-contrast]`; it renders
  in light mode unless `--dark` or `--increase-contrast` (combinable) ask otherwise. The image is the whole window:
  the title bar with the toolbar above content of `--width`×`--height`.
  `--budget <state>` shows the budget screen of the test budget "Business" (today 24.10.2026) in a state (`screen`,
  `edit`, `quick-budget`, `calculator`, `collapsed-header`, `collapsed-all`, `drag`, `hover`, `uncategorized`, `targets`
  with the Verfügbar markers) or with one of its popups open (`quick-budget-menu`, `quick-budget-confirm`, `add-master`,
  `add-sub`, `edit-category`, `edit-master`, `rename-error`, `delete-category`, `summary`, `income-summary`,
  `uncategorized-summary`, `outflow-help`, `account-view`, `cover`, `move`, `target`, `target-editor`, `assign`);
  `--month 2023-05` picks the first shown month and `--test-edits` adds the session's later edits (`summary` and
  `account-view` need them).
  `--edit <state>` first types into the register with real key events (`existing`, `new`, `payee-dropdown`,
  `category-dropdown`, `split`, `errors`, `unassigned`, `calendar`, `calculator`, `invalid-payee`,
  `income-check`, `account-field`); `--trace` prints the editor state afterwards. `--ops <state>` opens register
  operations instead (`action-menu`, `context-menu`, `search-suggestions`, `search-active`, `date-filter`,
  `notifiers`, `column-menu`, `running-balance`, `approve-popup`, `needs-category`,
  `reconcile-help` (with `--account "Alle Konten"`), `delete-dialog`, `make-recurring`); menus, native in the app, are drawn inline. `--ops keys` sends real key and mouse events and
  prints what the register did with them (add `--native-menus` to run it with native menus); without a menu bar,
  menu key equivalents run their Buchungen menu command and ⌘A sends Select All's `selectAll:`. `--ui <state>` opens a
  reconciliation, scheduler, account or payee settings state through the view models (`rec-statement-dialog`,
  `rec-footer`, `sched-pane`, `sched-edit`, `account-add`, `account-edit`, `account-adjusted`, `account-balance`,
  `account-balance-check`, `rename-payee`, `payee-settings`, `payee-settings-multi`, `payee-settings-empty`,
  `payee-settings-category`); it runs before `--ops`, so both can be combined. Open sheets and alerts are drawn over
  the window.

## Gates

- `swift build -Xswiftc -warnings-as-errors`
- `swift test`
- `swift format lint --strict --recursive Package.swift Sources Tests`

# Decisions

## 0001. External ids live in their own table

Accepted, 2026-10-09

External ids are kept in `transaction_origins` (transaction, account, source, external id; unique per account,
source and external id) instead of a column on the transaction. When an import is matched to an existing
transaction, the existing one survives with its id (API clients hold it) and gets the import's origin attached,
so a re-import still finds it and is not imported twice; `source` on the transaction stays where it was first
created.

Until the match is decided, the import is a row of its own with `matched_transaction_id`: a pending proposal that
counts nowhere (listings and balances skip it), one per existing transaction, with its account and amount fixed
while it is open. Accepting moves its origins to the existing transaction, which takes the import's date and cleared
state and keeps its category and memo where it has them, and removes the row; rejecting ("Trennen") clears the
pointer and approves the import as a transaction of its own. Origins follow their transaction when it moves to
another account; a move into an account that has the same external id from the same source is refused.

### Considered options

- An `external_id` column on the transaction: one id per transaction, so a matched transaction loses either its
  own id (breaking API clients) or the import's id (the next import creates a duplicate).
- Keeping the imported row as a hidden duplicate after the match: dedupes, but leaves two rows for one booking that
  every balance, report and API response has to skip for good, not only while the match is open.

## 0002. The YNAB re-import wipes and reloads the budget

Accepted, 2026-10-09

- **Context:** The YNAB import runs again and again until the switch, and YNAB stays the source of truth until
  then; Abakus holds nothing of its own yet, and the API clients only move to Abakus afterwards.
- **Decision:** Each run deletes the whole budget domain (everything but users and the internal Ready to Assign)
  and loads the YNAB export anew, in one database transaction; it refuses to run once any transaction, deleted
  ones included, has a source other than `ynab`. Matching by YNAB ids (an id column on accounts, groups,
  categories and payees, updates through the Ledger's rules) was rejected as much more work for data that does not
  need to survive.
- **Consequences:** Ids change on every run, so nothing may hold them before the switch; accounts or categories
  created in Abakus without transactions are lost on a re-import, and after the switch the import cannot be used
  to catch up.

## 0003. Categories are deleted only with a transfer

Accepted, 2026-10-10. Replaces "hidden, never deleted" from the spec.

- **Context:** After the switch YNAB no longer shapes the categories, so Abakus has to add, rename and remove
  them. Hiding (YNAB's way to retire a category) keeps old envelopes around for good and needs a second kind of
  category everywhere: in the budget, the pickers, filling and name lookups.
- **Decision:** There is no hiding. Deleting a category names a regular category that takes over everything:
  transactions and split lines (deleted ones, match proposals and the budget side of transfers to tracking accounts
  included), payees' last categories and the assignments, added per month. Targets and snoozes go with the
  category. Reconciled transactions change too, after the user confirms it. A group is deleted only when it is
  empty. YNAB's hidden flag stays on groups and categories for the import and its check; the budget ignores it.
- **Consequences:** History keeps its references and every past month's Ready to Assign and sum of available stay
  as they were, as long as neither category was overspent in a month where the other had money; merging
  envelopes covers such overspending, so Ready to Assign changes from that month on, as in YNAB. Deleted
  categories are gone, also from the API; there is no undo.

## 0004. The UI moves to Setzkasten

Accepted, 2026-10-13. Replaces felt-css with Bootstrap class names.

- **Context:** Abakus was built on felt-css (clean look) with Bootstrap markup from `core_components`. The owner's
  other apps share Setzkasten, a Phoenix component library on Tailwind CSS 4 and daisyUI 5 with its own design
  rules, tokens, themes and app shell. Two visual systems mean twice the upkeep and two ways to build a screen.
- **Decision:** Abakus uses Setzkasten for its shell, components, themes and conventions; felt-css, its CDN link
  and CSP entries, the Bootstrap classes and the click dummy in `mockup/` are gone. Lucide icons live in
  `assets/vendor/lucide`.
- **Consequences:**
  - Domain UI (budget grid, month strip, register grid, reconcile) stays app CSS in the partials under
    `assets/css/`, written on Setzkasten's tokens.
  - A Setzkasten bug or missing piece is fixed upstream in `shostakovich/setzkasten`, not worked around in the app.
  - Confirmations use Setzkasten's confirm dialog instead of `data-confirm`.
  - Stored theme and sidebar choices reset once: Setzkasten keeps them under `setzkasten:theme` and
    `setzkasten:sidebar`.

## 0005. Budget, shared expenses and portfolios are one app

Accepted, 2026-10-15

- **Context:** The household ran three apps (Abakus, Zipfelkasse, zipfelfolio) with three addresses, sign-ins and
  copies of the same stack; shared expenses and portfolio values only reached the budget through sync APIs.
- **Decision:** One release and one SQLite database with three areas, Budget, Kasse and Depot, each with its own
  contexts and table prefix (`kasse_…`, `depot_…`); the other two repositories are archived (#43, #44).
- **Consequences:** Areas can write to each other in one database transaction instead of syncing; the release grows
  every area's dependencies and jobs, and clashing terms (account, transaction, category) need area-qualified names.

## 0006. Shared expenses are linked to the budget, not synced

Accepted, 2026-10-15

- **Context:** The Kasse synced each person's share to YNAB with fingerprints and retries; with both in one database a
  sync would only copy data the app already holds.
- **Decision:** The budget owner's share of each expense is a transaction in the account fed by `shared_expenses`,
  written with the expense through the Ledger. The Kasse leads: a change there overwrites the fields it changed,
  while the register's own category, memo, flag and approval stay until the Kasse changes the same field.
- **Consequences:** That account's balance is the owner's Kasse balance by construction, so it is never reconciled;
  amount, date and payee of linked transactions cannot be edited in the register.

## 0007. The budget has one owner

Accepted, 2026-10-15. Replaces "domain tables have no user: all users see everything" from the spec.

- **Context:** The Kasse brings in a member who shares expenses but must not see the budget.
- **Decision:** Exactly one user owns the budget, set by the invite; only that user sees the Budget area. A per-user
  "budget access" flag was rejected as permissions for a second budget user nobody has.
- **Consequences:** Budget tables still carry no user; a second person in the budget would need this decision undone.

## 0008. Kasse participants sign in

Accepted, 2026-10-15. Replaces Zipfelkasse's "no login, the person is kept in a session cookie".

- **Context:** Behind Abakus's sign-in, a picker that lets anyone be anyone would bypass the budget owner's privacy.
- **Decision:** Every participant is a user, with magic link and passkeys; adding a participant invites a user, and
  the "who are you" picker is gone.
- **Consequences:** Every participant needs an email address and a passkey; there are no participants without a sign-in.

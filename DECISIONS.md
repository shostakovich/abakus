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

Accepted, 2026-10-15; partly superseded by 0017, 2026-10-16

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
  while the register's own category, memo, flag and approval stay; only a change of the expense's Kasse category
  writes the category again.
- **Consequences:** That account's balance is the owner's Kasse balance by construction, so it is never reconciled;
  amount, date and payee of linked transactions cannot be edited in the register, and they are deleted only with
  their expense. The link keeps the category and memo the Kasse wrote last; where the transaction differs from them,
  the register overrode the field, whichever register action did it (#48).

## 0007. The budget has one owner

Accepted, 2026-10-15; partly superseded by 0019, 2026-10-16. Replaces "domain tables have no user: all users see
everything" from the spec.

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

## 0009. Kasse money is cents, split by largest remainder rotated by expense id

Accepted, 2026-10-15. From Zipfelkasse, where it was decided first.

- **Context:** Shares must add up to the expense exactly and Kasse balances to zero, and the cent that does not
  divide evenly must not always fall on the same participant.
- **Decision:** Money is integer euro cents; a foreign amount is stored in its currency's minor units and
  converted with rounding half away from zero. Shares are allocated by largest remainder over the participants
  ordered by id; ties take turns by the expense id.
- **Consequences:** No floating-point drift and reproducible splits: the same expense always splits the same way,
  and the form previews the split with the next id. Changing the allocation would change stored shares, so it
  stays fixed.

## 0010. Case-folded columns instead of a custom SQL function

Accepted, 2026-10-15. From Zipfelkasse, where it was decided first.

- **Context:** The Kasse's search, duplicate checks, recurring skips and statistics by title must ignore case the
  Unicode way ("ß" as "ss", umlauts); SQLite's `lower()` and `LIKE` fold only ASCII. Exqlite cannot register
  custom SQL functions, and one would exist neither in an SQL sandbox nor in the `sqlite3` shell.
- **Decision:** `kasse_expenses.title_folded` and `notes_folded` hold `:string.casefold/1` of title and notes,
  written by the changeset on every insert and update; queries compare them with a folded term.
- **Consequences:** Plain SQL works everywhere. Every write must go through the changeset (or set the columns
  itself), and the texts are stored twice.

## 0011. The Kasse's YNAB sync keeps the Kasse as the source of truth

Accepted, 2026-10-15. From Zipfelkasse, where it was decided first; it lasts until the switch to Abakus (ADR 0006).

- **Context:** Each participant can mirror their share of every expense into their own YNAB account. Expenses change
  and disappear after they were synced, and requests can fail with an unknown outcome.
- **Decision:** The Kasse creates, updates and deletes its transactions in YNAB and never takes changes back. No
  `import_id` (YNAB would merge the imports with reimbursement transfers of the same amount); every memo ends with
  the marker `zipfelkasse #<expense id>`, which finds transactions after an unclear outcome or a change of account.
  A fingerprint (`v1\0date\0milliunits\0payee\0memo\0category`, the first 16 bytes of SHA-256 as hex) per
  share decides whether an update is needed.
- **Consequences:** Date, amount, payee or memo edited in YNAB are overwritten when the expense changes. The
  fingerprint and memo format must stay byte-identical, also across the move into Abakus, or every transaction looks
  changed; the marker keeps the old app's name for that reason, and the import keeps expense ids. The tokens are
  stored in the database, so backups are private, and a copy of the database in development reaches YNAB only when
  `YNAB_BASE_URL` points there.

## 0012. A stateless MCP server behind a secret path and an address filter

Accepted, 2026-10-15. From Zipfelkasse, where it was decided first.

- **Context:** AI assistants should analyse the shared expenses and enter new ones, but they cannot sign in with a
  passkey, and the data is private.
- **Decision:** Only MCP protocol version 2026-07-28, stateless (no handshake, session or SSE). The one endpoint is
  `/mcp/<MCP_SECRET>`, compared in constant time, for client addresses in `MCP_ALLOWED_CIDRS` only, and refuses
  browsers (any `Origin`). Tools only read, except two that add Kasse entries. `sql_query` runs on an in-memory copy
  of the Kasse's tables (`kasse_…` without the YNAB ones), read-only, without ATTACH or pragmas, cancelled after 2
  seconds.
- **Consequences:** No server state to lose and no older protocol versions to support; clients that do not speak
  2026-07-28 cannot connect. A query can never change or lock the real database or see the YNAB tokens, users or the
  budget, at the cost of copying the data per query. The budget's tools join the same endpoint and its rules.

## 0013. One Depot transaction per business event

Accepted, 2026-10-16. From zipfelfolio, where it was decided first.

- **Context:** Portfolio Performance keeps a purchase in memory as two linked entries (portfolio and account), but its
  file stores it as one transaction with `other*` fields.
- **Decision:** The Depot follows the file: one transaction with a portfolio side, an account side or both;
  calculations that need a per-side view derive it.
- **Consequences:** The import maps one record to one record, both sides can never drift apart, and the booking form
  edits one thing. Unlike the budget's transfers, there is no pair of transactions to keep in step.

## 0014. Depot holdings are computed on every request

Accepted, 2026-10-16. From zipfelfolio, where it was decided first.

- **Context:** The overview, holdings and charts need holdings and values for any date. A household has at most a few
  thousand Depot transactions and a handful of securities, and a booking, an import or a price fix can change any
  past date.
- **Decision:** A pure module computes holdings and values from transactions and prices on every request; no stored
  daily snapshots.
- **Consequences:** Nothing to invalidate or rebuild after a change. Every page load repeats the work, so a much
  longer history would need caching or snapshots later.

## 0015. Depot receipts are recognised locally from their text

Accepted, 2026-10-16. From zipfelfolio, where it was decided first.

- **Context:** Bank receipts carry account numbers and amounts, and they should stay on the home server.
- **Decision:** The Depot sends a receipt's text (Paperless' `content`, else `pdftotext`) to any OpenAI-compatible
  chat API with a JSON schema, such as Ollama on the home server (`RECEIPT_MODEL_URL`, `RECEIPT_MODEL`,
  `RECEIPT_MODEL_KEY`); not a hosted model with the PDF.
- **Consequences:** No receipt needs to leave the house and any local or hosted model fits. Scanned receipts without a
  text layer depend on Paperless' OCR, a CPU-bound model takes about a minute per receipt, and the image needs
  poppler-utils. Without a model a receipt opens an empty form.

## 0016. Paperless access per user

Accepted, 2026-10-16. From zipfelfolio, where it was decided first.

- **Context:** Receipts belong to the user whose portfolio they concern; other users may have their own Paperless
  instance or none.
- **Decision:** Each user enters Paperless URL, token and tag in their Depot settings (`depot_settings`); not one
  global connection in the environment.
- **Consequences:** Ownership is clear without guessing from depot numbers, and nothing needs a redeploy. The token
  lives in the database, so a database backup grants access to Paperless. Any user with a portfolio can make the
  server call the URL they enter, which is acceptable for a self-hosted app with invited users only.

## 0017. A portfolio is a kind of account, not an area

Accepted, 2026-10-16. Changes the three areas of 0005 into two (#56).

- **Context:** With Budget and Depot as separate areas, one portfolio appeared as a Depot page, as part of a tracking
  account fed by `portfolio` and through its Verrechnungskonto, which is often the same bank account as a budget
  account.
- **Decision:** The UI areas are Finanzen (budget and portfolios) and Kasse. Each of the budget owner's portfolios is
  exactly one tracking account, and each Verrechnungskonto is a budget account, the cash of one portfolio, or neither.
  Users with portfolios and no budget see Finanzen without the budget; the budget keeps one owner (0007).
- **Consequences:** A portfolio shows once, as an account with its holdings, and Vermögen is the total of all
  accounts. Several portfolios can no longer feed one tracking account, the accounts fed that way today are closed
  at the switch, and the Depot code and tables keep their name although "Depot" is no longer an area.

## 0018. Depot cash flows are linked transactions in the budget

Accepted, 2026-10-16 (#56).

- **Context:** Money moved into a portfolio left a budget account uncategorised, and the daily value change of the
  portfolio's account booked it again, mixed with the market movement.
- **Decision:** Flows between a portfolio and a Verrechnungskonto that is a budget account are linked transactions
  in that account, as 0006 does for the Kasse: the Depot transaction leads amount, date and payee, purchases get the
  category chosen when linking, inflows go to Ready to Assign, and nothing before the link's start date is booked.
  Flows inside a portfolio's own cash stay out of the budget.
- **Consequences:** Investing becomes budget spending, so every savings plan run is a transaction to approve, and
  the value change shrinks to market movement and income inside the portfolio. Every Depot write, including PP
  re-imports, must keep its linked transactions in the same database transaction.

## 0019. Every context takes the scope

Accepted, 2026-10-16 (#73).

- **Context:** The Depot took `%Scope{}`, the Kasse a person's id with access checked only in the router, and the
  budget nothing, its tables carrying no user (0007), so a job or an MCP tool could reach any data, and the budget
  owner was checked in five places.
- **Decision:** Every public context function called from outside its context takes `%Scope{}`, reads included.
  Callers without a person (jobs, release and mix tasks, MCP reads) pass `Scope.system()`, MCP writes act as the
  expense's payer; separate internal entry points for jobs were rejected as a second API.
- **Consequences:** Each context must allow the system scope explicitly where it is valid, and the Kasse refuses a
  signed-in user who is not a person itself. Budget tables get their owner's `user_id`, so 0007's "budget tables
  carry no user" no longer holds, while the budget keeps one owner.

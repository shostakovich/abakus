# Abakus — spec

Self-hosted envelope budgeting for one household. Replaces YNAB (and Actual Budget) with only the features the
owner uses: YNAB's budgeting rules, Actual's multi-month view, reconciling, file import, bank sync, a
YNAB-compatible API and MCP. Open source, benevolent dictator: no PRs, forks welcome.

The click dummy in `mockup/` shows the intended screens (example data only).

## Scope

- one budget, 1–2 users, EUR only
- mobile and desktop, one LiveView app, installable as PWA
- self-hosted, reachable from the internet over HTTPS only (behind the operator's reverse proxy)
- online only; offline entry comes in v3, not a sync protocol like Actual's CRDTs

Not in scope for now: reports beyond the budget view, payee rename rules, multiple budgets, other currencies,
investment tracking (that is a separate portfolio app). No scheduled transactions: the only recurring one (rent)
comes from a shared-expenses app's recurring expenses through the API.

## Stack

- Elixir, Phoenix 1.8, LiveView, SQLite (`ecto_sqlite3`), esbuild, one amd64 container
- felt-css (`https://felt-css.rocu.de/felt.css`), Bootstrap class names in `core_components`, clean look
  only (no felt look)
- HTTP: `req`; mail: `swoosh`
- New dependencies only with a reason
- SQLite conventions: `default_transaction_mode: :immediate`, WAL, `:utc_datetime_usec`, synchronous DB tests,
  `pool_size: 1` in test

## Login

The context is `Abakus.Users` (an "account" is a bank account here):

- `phx.gen.auth` magic link as base and recovery; no passwords, no sign-up. An invite creates the user and
  mails a sign-in link at once: `mix abakus.invite EMAIL`, in the container
  `bin/abakus eval 'Abakus.Release.invite("EMAIL")'`
- Passkeys implemented in-house with `:crypto`, `:public_key`, `JSON`; attestation `none`; discoverable
  credentials; relying party id = the configured host (`PHX_HOST`); challenges are valid 5 minutes, one open
  per session, dropped from the session on any attempt. A sign-in challenge travels in the signed session, so
  anonymous requests store nothing; a challenge that signed someone in is recorded (as a hash, in ETS) until
  it expires and refused again, failed attempts record nothing. A registration challenge stays on the server;
  at most 1 000 are open at a time, beyond that the server asks to try again. Changing passkeys or the email
  needs a sign-in within 10 minutes, which sends the user back to the settings afterwards; signing in again
  keeps open tabs working. A new passkey is announced by mail
- Tests fake the authenticator with `:crypto` and break every check once
- Public internet: nothing is reachable without a session except `/up`, `/api/v1` (bearer token) and
  `/mcp/<secret>` (a test walks all routes)
- Magic link requests: at most 3 per address (trimmed, lower case) per 15 minutes, the validity of a link, and
  30 in total per hour, sliding windows in ETS. Unknown addresses count in a bucket of their own (30 per hour),
  so they cannot lock users out. Over a limit no mail goes out, the page answers the same and the log gets a
  warning with a short hash of the address; mails are sent in the background (at most 50 at a time, more
  requests are dropped with the same answer), so the response time tells nothing either
- Cookies `HttpOnly`, `SameSite=Lax`, `secure` behind https
- CSP with a nonce per request (for the inline theme script) on every response, error pages and static files
  included; only the LiveView socket's transport responses (`/live`) bypass the plugs. `default-src 'self'`,
  scripts `'self'` + nonce, styles and their images also from `felt-css.rocu.de` (images also `data:`), fonts
  `'self'`, `connect-src` `'self'` + the endpoint's `wss://` (`ws://` in development), `object-src` and
  `frame-ancestors 'none'`, `base-uri` and `form-action` `'self'`. No `'unsafe-inline'`: LiveView sets styles
  through the CSSOM, which CSP allows. Only the development mailbox gets a looser policy. Error pages are German

## Domain

Mirrors YNAB so the import is lossless and the API can speak YNAB's format.

Terms: [`CONTEXT.md`](../CONTEXT.md). Two contexts: `Abakus.Ledger` (accounts, payees, transactions) and
`Abakus.Categories` (groups, categories, assignments, targets); `Abakus.Budget` is the pure math on top. Domain
tables have no user: all users see everything.

- **Account**: name, kind (checking, savings, cash, tracking), fed by (`portfolio`: value from a portfolio app,
  `shared_expenses`: transactions from a shared-expenses app; filled via the API, so the UI hides manual entry and
  file import for it; the Ledger accepts both), closed, note, position, last reconciled at. Budget account = not
  tracking (derived; a kind never crosses that line). No credit cards or loans. Closed, never deleted.
- **Payee**: name, transfer account, last used category. Each account has a transfer payee "Transfer : <account
  name>" as in YNAB, created and renamed with the account. Other payees are unique by lookup key.
- **Category group** and **category**: name, hidden, position, note, internal. Hidden, never deleted; lookup keys of
  categories are not unique (an old hidden "Urlaub" next to "🏖️ Urlaub"); groups have none. A migration creates
  YNAB's internal group "Internal Master Category" with "Inflow: Ready to Assign" (UI "Zu verteilen"); internal ones
  are not listed, not editable and take no assignments or targets. Ready to Assign's lookup key is reserved: no
  other category takes it, and looking it up finds only Ready to Assign.
- **Names** usually start with an emoji ("🛒 Lebensmittel"), stored as entered. Lookups by name (MCP, search,
  suggestions, import) use the lookup key: Unicode NFC, without emoji and symbols (incl. ZWJ sequences, skin tones,
  keycaps, flags, variation selectors), whitespace collapsed, lower case, "ß" as "ss"; emoji-only names keep their
  emoji without variation selectors and skin tones ("❤️" = "❤", "👍🏽" = "👍"). They prefer visible regular
  categories and regular payees over transfer payees, else report not found or ambiguous.
- **Amounts** are integer cents, at most 100 billion euros either way (10^13 cents) on transactions,
  subtransactions, assignments and targets.
- **Months** (assignment, target version, snooze) are stored as the first of the month; every function takes any day
  of it, as a date or ISO 8601 string.
- **Assignment**: category, month, amount (may be negative); one per category and month
- **Target version**: category, from month, cadence (monthly, yearly, none = no target from then on), amount
  (positive), due on (yearly only, not before from month), set aside (YNAB `goal_needs_whole_amount`: "set aside
  another" vs. "refill up to"). A version applies until the next one, so changing a target keeps past months.
- **Target snooze**: category, month; one per category and month (snoozing again returns the one there is)
- **Transaction**: account, date, amount (signed), payee, category, memo, cleared (`uncleared`, `cleared`,
  `reconciled`), approved (manual entries by default, imports and API entries not), flag (red, orange, yellow,
  green, blue, purple), transfer counterpart (a transaction, or for a split's transfer its subtransaction), source
  (`manual`, `ynab`, `file`, `bank`, `api`: where it was created, set once), matched transaction (see match
  proposals), deleted at (soft delete, the API reports deletions; deleted transactions cannot be changed). The
  register is what counts: transactions not deleted and no match proposal (`Ledger.in_register/0`).
- **Reconciled lock**: the Ledger refuses any change that alters a reconciled transaction ("ist abgeschlossen"),
  leaving the reconciled state included, whether made on it directly or through a transfer: its counterpart's or a
  split's subtransaction's edit kept in step (amount, date, memo, account, category), released (payee no longer a
  transfer, subtransaction removed, turned into a split) or deleted with it. The caller passes
  `reconciled: :confirmed` to `update_transaction/3`, `delete_transaction/2` or `accept_match/2` after asking; the
  UI asks first, the API does not pass it and answers 409.
- **Transfers**: a transaction or subtransaction is a transfer when its payee is a transfer payee; never to its own
  account, and a split is none as a whole. The Ledger alone creates and keeps the counterpart in the payee's
  account (amount negated, same date and memo, payee = the other account's transfer payee; cleared, approved and
  flag per side), moves it when payee or account change and removes it when the payee stops being a transfer
  payee. Deleting either side deletes both, deleting a split deletes its subtransactions' counterparts; the
  counterpart of a subtransaction is changed and deleted in its split. Transfers to closed accounts are allowed.
- **Category rule**, checked by `Ledger.create_transaction/1` and `update_transaction/3` with all accounts
  involved: none in tracking accounts, none for transfers between budget accounts, one on the budget side of a
  transfer between a budget and a tracking account (given as `counterpart_category_id` when that side is the
  counterpart), none on a split; a split's subtransactions are checked whenever its account changes.
- **Subtransaction** (split): position, amount, category, payee, memo, transfer counterpart (a subtransaction can
  be a transfer, as in YNAB). At least two adding up to the parent; deleted and soft-deleted with it.
- **Match proposal**: an import from a file or the bank with a matched transaction in the same account with the same
  amount, which is in the register (not deleted, no proposal itself) and not reconciled; one open proposal per
  transaction. It leaves its payee's last category alone. While it is open, account and amount of both are fixed
  (also for a counterpart, whose other side then keeps its amount and payee). It counts nowhere (not listed, no
  balance, no budget) until accepted (checked again, so a transaction reconciled meanwhile refuses it; merged into
  the existing transaction: that one keeps its id and, where it has them, its category and memo, else takes the
  import's; it takes the import's date, cleared state and origins; the import row goes) or rejected ("Trennen": the
  import stays as a transaction of its own and is approved). Deleting the matched transaction leaves the import
  unapproved; a deleted proposal proposes nothing.
- **Transaction origin**: transaction, account, source, external id; unique per account, source and external id
  (FITID, provider or YNAB id). A transaction matched to an import keeps the import's origin, so re-imports
  dedupe ([ADR 0001](adr/0001-transaction-origins.md)); origins move with their transaction to another account.
  Moving a transaction, or a counterpart, into an account that has one of its external ids from the same source
  already is refused.
- References are restricted: nothing that history points to can be deleted. The contexts check references before
  writing, so a missing one is a validation error ("existiert nicht"), not a constraint error.
- **Bank connection**: provider, bank, session id, valid until, linked accounts (provider account id → account),
  last sync, last error
- **API token**: name, SHA-256 of the token, created at, last used at
- **User**, **passkey**, **user token** (`phx.gen.auth` plus passkeys, see Login)

Amounts are integers in cents. The API converts to and from YNAB milliunits (× 10) and rejects amounts that are
not whole cents.

## Budget rules

YNAB's math, with one deliberate difference: money is never borrowed from a later month. The method is YNAB's
too: every euro gets assigned, and overspending is dealt with. The UI treats RTA > 0 and overspent categories as
open tasks (green "assign" box, red "n overspent" chip, "cover overspending" popover that picks the source
category), and RTA = 0 with nothing overspent as the resting state.

- **Ready to Assign (RTA)** per month m, cumulative:
  RTA(m) = income up to and including m − assigned up to and including m − overspending of the months before m
- **Available** per category and month = max(available last month, 0) + assigned + activity; for the first month
  the carry is 0
- **Overspending** (negative available): shown red; the category starts the next month at 0 and the amount is
  subtracted from RTA. There are no credit cards, so YNAB's credit overspending and payment categories do not
  exist.
- Shown as "Zu verteilen" in a month: RTA(m) − assigned in later months (as YNAB's UI does; the API's
  `to_be_budgeted` is RTA(m) without that subtraction), with a line "assigned in future months"
- Both formulas reproduce YNAB's API numbers exactly (`to_be_budgeted`, category `balance`), checked against a
  real budget: every month and every category-month matched.
- **No borrowing** (the difference): YNAB lets assignments push RTA below zero, which silently takes the money
  from next month's income. Abakus refuses an assignment that would make RTA negative in its month or any later
  month; the input shows how much is left. RTA can still turn negative through overspending; then it is red with
  the action "cover from categories". Imported history keeps its negative months as they were.
- Transfers between budget accounts have no category; transfers between a budget and a tracking account need one
- Income is what is categorised "Ready to Assign", the only income category; it is available in the month it is
  dated. Inflows to other categories (refunds) are valid and count as those categories' activity.
- Targets: only YNAB's **needed for spending** (`NEED`), the one type in use:
  - monthly amount, or yearly amount due on a date (spread over the months until then)
  - "set aside another" (`goal_needs_whole_amount` true: assigned this month counts) or "refill up to" (false:
    available counts)
  - per category and month: underfunded amount, progress, snoozed; one action fills all underfunded categories
    from RTA (in category order, as far as RTA reaches)
  - UI copied from YNAB: progress bar and status under the name ("Finanziert", "Im Plan", "Noch 13,99 € nötig
    bis zum 31.", "Überzogen"), pill icons, inspector with ring, "assign X more" button and target editor
  - other goal types (`TB`, `TBD`, `MF`, `DEBT`) only if needed later
- All of this is one pure module (`Abakus.Budget`) computed from assignments and transactions; months are not
  stored as snapshots. Property tests plus fixtures checked against YNAB's own numbers (see acceptance v1).

## Budget view

- Desktop: months side by side like YNAB 4 and Actual; 1, 2 or 3 depending on the window width, recalculated on
  resize, no manual setting; month strip with year, prev/next/today. Each month header explains RTA like YNAB 4: not
  assigned last month − overspent last month + income − assigned = RTA.
  Category groups collapsible. Per month: assigned (editable), activity, available (pill: positive, zero,
  underfunded, negative); categories with a target show a progress bar. Month header with income, assigned,
  spent, underfunded and "fill underfunded". RTA shown once at the top.
- Phone: one month, swipe or arrows; a row shows category and available; tapping opens a sheet with the assigned
  input and quick actions (meet target, as last month, spent last month, cover overspending), the target editor
  and "move money" between categories.
- The first visible month lives in the URL; the number of months follows the window.

## Accounts and reconciling

- Account list grouped into budget and tracking accounts with working and cleared balance
- Register with filters and search; unapproved imported transactions highlighted, approve one or all
- Transaction form: account, date, payee with suggestions, category suggested from the payee's last category,
  outflow/inflow, memo, splits, transfers
- **Reconcile** as in YNAB: a popover compares the latest bank balance (from bank sync, or the ledger balance
  of the last file import) with the cleared balance; equal → one click marks all cleared transactions
  reconciled. Different, or no bank balance → enter the bank balance, Abakus shows the difference and can create
  an adjustment transaction (category "Ready to Assign", payee "Ausgleichsbuchung") before locking. Reconciled
  transactions need a confirmation to edit.
- New imported transactions: banner "n neue Buchungen zu bestätigen oder zu kategorisieren", rows marked until
  approved, already categorised from the payee's last category; approve one, selected or all

## Import

All imports land as unapproved, `cleared`, with an external id. A transaction is never imported twice from the
same source; across sources (and against manual entries) a match is proposed, never merged silently.

- **Dedupe within a source**: by (account, source, external id) — FITID for files, the provider's transaction id
  for bank sync
- **Matching**: same account, same amount, date within ±10 days, existing transaction not yet matched or
  imported and not reconciled → shown as "matches manual entry of …"; approving merges (manual category and memo
  win where present, date and cleared state from the import)
- **Category suggestion**: the payee's last category
- **File import (v1)**: OFX/QFX exports from a banking app (SGML OFX 1.x and XML OFX 2.x); hand-written parser for
  `BANKACCTFROM`/`CCACCTFROM`, `STMTTRN` (`DTPOSTED`, `TRNAMT`, `FITID`, `NAME`, `MEMO`), `LEDGERBAL`. Account
  mapping by account id from the file, remembered. Preview with counts (new, already there, matched) before
  importing. CSV only if a bank needs it later.
- **Bank sync (v2)**: Enable Banking (free restricted mode: only the owner's linked accounts), the only free
  aggregator that still accepts individuals (GoCardless closed sign-ups in 2025). Covers the common German
  banks; no FinTS. Template: Actual's `packages/sync-server/src/app-enablebanking/` (MIT).
  - Auth: own RSA key; every request carries an RS256 JWT (`kid` = application id, `iss` `enablebanking.com`,
    `aud` `api.enablebanking.com`, ≤ 24 h), signed with `:public_key`
  - Flow: `GET /aspsps` → `POST /auth` (bank, redirect URL, `valid_until` = the bank's
    `maximum_consent_validity`, not Actual's 90-day cap) → bank → callback with `code` → `POST /sessions` →
    `GET /accounts/{id}/balances`, `GET /accounts/{id}/transactions` (paging via `continuation_key`)
  - Unattended sync at most 4 times per day per account (PSD2 limit), plus "sync now"
  - Consent lasts 90–180 days depending on the bank; mail and banner 14 and 3 days before it expires; renewing
    is one redirect
  - The bank balance is stored per sync and offered when reconciling

## API (YNAB-compatible subset)

Exactly what the existing YNAB API clients (a shared-expenses app) use today, so they only need a new base URL
and token. Same paths, field names, milliunits, envelopes (`{"data": …}`) and error format
(`{"error": {"id", "name", "detail"}}`) as YNAB API v1 with "plans".

- Auth: `Authorization: Bearer <token>`; tokens are created and revoked in the settings, stored hashed
- `GET /api/v1/plans?include_accounts=true` — the one budget with its accounts
- `GET /api/v1/plans/{plan_id}/categories`
- `GET /api/v1/plans/{plan_id}/accounts/{account_id}`
- `GET /api/v1/plans/{plan_id}/accounts/{account_id}/transactions` (optional `since_date`; like YNAB without
  deleted ones)
- `POST /api/v1/plans/{plan_id}/transactions` with `{"transactions": […]}`
- `PATCH /api/v1/plans/{plan_id}/transactions` with `{"transactions": […]}` (by `id`)
- `DELETE /api/v1/plans/{plan_id}/transactions/{transaction_id}`
- Transaction fields: `id`, `date`, `amount`, `payee_name`, `memo`, `account_id`, `category_id`, `cleared`,
  `approved`, `deleted`; reconciled transactions can be read but not changed (409)
- Accounts carry YNAB's `balance`, `cleared_balance` and `uncleared_balance`
- Contract: the client's own fake YNAB server describes what it expects; Abakus has request specs for the same
  cases. Other YNAB endpoints only when a client needs them (e.g. a portfolio app's FI forecast).

## Tracking accounts

Only used for the portfolios (securities accounts and their cash accounts). Their value comes from a portfolio app
through the same API, the way YNAB tools post market values:

- Money moving into a portfolio is a transfer from a budget account, categorised (e.g. savings) in Abakus
- The portfolio app reads the account (`balance`) and posts the difference to its own value as one transaction,
  payee "Wertänderung", approved and cleared; nothing else changes the account
- Accounts that no aggregator reaches (e.g. a broker's settlement account) are covered this way too
- Until the portfolio app does this, the values imported from YNAB stay and can be adjusted by hand

## MCP

At `/mcp/<MCP_SECRET>` (off without the secret), interface in English, data as entered.

- Read: `accounts` (balances, cleared, last reconciled), `budget` (RTA and per category for one or more months),
  `search_transactions`, `statistics` (spending by category, payee, month; previous year comparison),
  `schema`, `sql_query` (`SELECT`/`WITH`, ≤ 500 rows, 2 s)
- Write: `create_transaction` (unapproved, so it shows up for review). Nothing is changed or deleted via MCP.

## YNAB import

- One-shot via the YNAB API with a personal access token (`YNAB_TOKEN`): accounts, payees, category groups and
  categories with targets (`goal_*` fields), assignments per month (`/months/{month}`), all transactions with
  splits and transfers, cleared and reconciled state, flags
- Repeatable until the switch: a re-import replaces everything that came from YNAB; the run reports what differs
- Checks after the import: per month RTA, and per category assigned, activity, available and underfunded
  (`goal_under_funded`) equal YNAB's `/months/{month}` numbers; account balances equal

## Screens

- **Budget**: multi-month view (see above)
- **Konten**: account list, register, reconcile
- **Buchung**: transaction form (FAB on phones)
- **Import & Sync**: file import with preview, bank connections with consent expiry
- **Mehr**: categories and groups, passkeys, API tokens, MCP, YNAB import, look and theme

State that should survive a reload (screen, month, number of months, account, filters) lives in the URL.

## Phases

### v1 — switch from YNAB

1. Skeleton: Phoenix, SQLite, felt-css `core_components`, login with magic link and passkeys, PWA manifest,
   container, deploy behind a reverse proxy, CI (format, credo, tests, assets)
2. Domain and `Abakus.Budget` incl. targets, with property tests
3. YNAB import with the checks above
4. Budget view, desktop and phone
5. Accounts, register, transaction form, splits, transfers, reconcile
6. OFX/QFX import with matching and approval
7. YNAB-compatible API; the existing YNAB API clients switched to Abakus

Acceptance: after importing the owner's YNAB budget, every month since the start shows the same RTA and the same
assigned, activity, available and underfunded per category as YNAB; account balances match; an OFX/QFX
export imports without duplicates; the existing YNAB API clients' sync runs against Abakus.

### v2 — bank sync and MCP

Enable Banking connections, scheduled sync, consent reminders by mail, bank balance in reconcile; MCP endpoint.

### v3 — offline entry

Only offline entry: a queue in the PWA that creates transactions while offline and sends them when back online
(create only, no edits, so no conflicts). Nothing else is planned for v3; scheduled transactions stay out.

## Operations

- One container; all data (the SQLite database) lives in the data volume at `/app/data`; backups are the
  operator's job
- Runs behind the operator's HTTPS reverse proxy, which sets `X-Forwarded-Proto`
- Config via env: `PHX_HOST` (required: the public host, also the passkey relying party id), `SECRET_KEY_BASE`,
  SMTP, `MCP_SECRET`, `YNAB_TOKEN` (import only), `ENABLE_BANKING_APP_ID` and the private key as a read-only
  mounted file (v2)
- `/up` checks the DB and, from v2, that no bank connection has failed for more than a day

## Open

- How YNAB computes `goal_under_funded` for yearly targets with a date in detail (check against the import)
- Whether the banking app's FITIDs stay stable across exports (test with two overlapping exports)
- Which banks show up in Enable Banking's restricted mode and their `maximum_consent_validity` (needs the
  owner's Enable Banking account)

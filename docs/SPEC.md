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

- `phx.gen.auth` magic link as base and recovery; no passwords, no sign-up (invite or mix task)
- Passkeys implemented in-house with `:crypto`, `:public_key`, `JSON`; attestation `none`; discoverable
  credentials; relying party id = the configured host (`PHX_HOST`)
- Tests fake the authenticator with `:crypto` and break every check once
- Public internet: magic link requests rate limited, secure cookies, CSP; nothing is reachable without a session
  except `/up`, `/api/v1` (bearer token) and `/mcp/<secret>`

## Domain

Mirrors YNAB so the import is lossless and the API can speak YNAB's format.

- **Account**: name, kind (checking, savings, cash, tracking), on budget, closed, note, position, last
  reconciled at. No credit cards or loans.
- **Payee**: name, transfer account (each account has a transfer payee as in YNAB), last used category
- **Category group** and **category**: name, hidden, position, note; internal category "Ready to Assign".
  Names usually start with an emoji ("🛒 Lebensmittel"); stored as entered, and lookups by name (MCP, search,
  suggestions) also match without the emoji and ignoring case.
- **Assignment**: category, month, amount
- **Target**: category, amount, cadence (monthly or yearly), target date (yearly), "refill up to" vs. "set
  aside", snoozed at
- **Transaction**: account, date, amount (signed), payee, category (none for transfers between budget accounts
  and for splits), memo, cleared (`uncleared`, `cleared`, `reconciled`), approved, flag colour, transfer
  counterpart, source (`manual`, `ynab`, `file`, `bank`, `api`), external id (per source), matched transaction,
  deleted at (soft delete, the API reports deletions)
- **Subtransaction** (split): amount, category, payee, memo; amounts add up to the parent
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
- Income can be categorised "Ready to Assign" only; it is available in the month it is dated
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
  imported → shown as "matches manual entry of …"; approving merges (manual category and memo win, date and
  cleared state from the import)
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

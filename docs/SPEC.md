# Abakus — spec

Self-hosted envelope budgeting for one household. Replaces YNAB (and Actual Budget) with only the features the
owner uses: YNAB's budgeting rules, Actual's multi-month view, reconciling, file import, bank sync and MCP. Open
source, benevolent dictator: no PRs, forks welcome.

## Scope

- one budget, 1–2 users, EUR only
- mobile and desktop, one LiveView app, installable as PWA
- self-hosted, reachable from the internet over HTTPS only (behind the operator's reverse proxy)
- online only; offline entry comes in v3, not a sync protocol like Actual's CRDTs

Not in scope for now: reports beyond the budget view, payee rename rules, multiple budgets, other currencies.
Investment tracking is the Depot (#44), part of Finanzen, each user's own portfolios. No scheduled transactions: the only
recurring one (rent) comes from the shared expenses' recurring expenses (#43).

## Stack

- Elixir, Phoenix 1.8, LiveView, SQLite (`ecto_sqlite3`), esbuild, one amd64 container
- Tailwind CSS 4 and daisyUI 5 with Setzkasten, the component library shared with the owner's other apps
  (ADR 0004)
- HTTP: `:httpc`; mail: `swoosh`
- New dependencies only with a reason
- SQLite conventions: `default_transaction_mode: :immediate`, WAL, `:utc_datetime_usec`, synchronous DB tests,
  `pool_size: 1` in test

## Login

The context is `Abakus.Users` (an "account" is a bank account here):

- `phx.gen.auth` magic link as base and recovery; no passwords, no sign-up. An invite creates the user and
  mails a sign-in link at once: `mix abakus.invite EMAIL`, in the container
  `bin/abakus eval 'Abakus.Release.invite("EMAIL")'`. The first user invited owns the budget
  ([ADR 0007](../DECISIONS.md))
- Areas ([ADR 0017](../DECISIONS.md)): Finanzen (the budget under `/budget`, the Depot under `/depot`) and the
  Kasse (`/kasse`), each with its own sidebar and dock on phones; a user sees only the areas they may use (the
  budget's pages: its owner; the Depot's: the budget owner and every user with a portfolio of their own; the
  Kasse: its active participants, [ADR 0008](../DECISIONS.md)), and anyone else gets 404 on their pages.
  Finanzen lists Budget, Vermögen, Alle Konten, Import & Sync, the open accounts, then Depots with the active
  portfolios; without the budget only Vermögen, Import & Sync and Depots. The Kasse lists Ausgaben, Salden and
  Aktivität. With one area the brand is its name; with more, a segmented switch tops the sidebar and the title in
  the top bar switches the area; switching opens the area's first page. `/` opens the area used last, kept in the
  session
- Passkeys implemented in-house with `:crypto`, `:public_key`, `JSON`; attestation `none`; discoverable
  credentials; relying party id = the configured host (`PHX_HOST`); challenges are valid 5 minutes, one open
  per session, dropped from the session on any attempt. A sign-in challenge travels in the signed session, so
  anonymous requests store nothing; a challenge that signed someone in is recorded (as a hash, in ETS) until
  it expires and refused again, failed attempts record nothing. A registration challenge stays on the server;
  at most 1 000 are open at a time, beyond that the server asks to try again. Changing passkeys or
  the email needs a sign-in within 10 minutes, which sends the user back to the settings afterwards; signing in
  again keeps open tabs working. A new passkey is announced by mail
- Tests fake the authenticator with `:crypto` and break every check once
- Public internet: nothing is reachable without a session except `/up` and `/mcp/<secret>` (a test walks all
  routes)
- Magic link requests: at most 3 per address (trimmed, lower case) per 15 minutes, the validity of a link, and
  30 in total per hour, sliding windows in ETS. Unknown addresses count in a bucket of their own (30 per hour),
  so they cannot lock users out. Over a limit no mail goes out, the page answers the same and the log gets a
  warning with a short hash of the address; mails are sent in the background (at most 50 at a time, more
  requests are dropped with the same answer), so the response time tells nothing either
- Cookies `HttpOnly`, `SameSite=Lax`, `secure` behind https
- CSP with a nonce per request (for the inline theme script) on every response, error pages and static files
  included; only the LiveView socket's transport responses (`/live`) bypass the plugs. `default-src 'self'`,
  scripts `'self'` + nonce, styles and fonts `'self'`, images `'self'` and `data:`, `connect-src` `'self'` + the endpoint's `wss://` (`ws://` in development), `object-src` and
  `frame-ancestors 'none'`, `base-uri` and `form-action` `'self'`. No `'unsafe-inline'`: LiveView sets styles
  through the CSSOM, which CSP allows. Only the development mailbox gets a looser policy. Error pages are German

## Domain

Mirrors YNAB.

Terms: [`CONTEXT.md`](../CONTEXT.md). Two contexts: `Abakus.Ledger` (accounts, payees, transactions) and
`Abakus.Categories` (groups, categories, assignments, targets); `Abakus.Budget` is the pure math on top. The budget
is its owner's ([ADR 0007](../DECISIONS.md)); its tables carry their owner's `user_id`, and both contexts see only
the rows of their caller's user (ADR 0019).

- **Account**: name, kind (checking, savings, cash, tracking), fed by (`portfolio`: value from the Depot,
  `shared_expenses`: the budget owner's shares of the Kasse's expenses; either way the UI hides manual entry, file
  import and reconcile for it, as its balance is the other area's; the Ledger accepts entries), closed, note,
  position, last reconciled at, the file's account it takes imports from (`BANKID`, `ACCTID`). Budget account = not
  tracking (derived; a kind never crosses that line). No credit cards or loans. Closed, never deleted.
- **Payee**: name, transfer account, last used category. Each account has a transfer payee "Transfer : <account
  name>" as in YNAB, created and renamed with the account. Other payees are unique by lookup key.
- **Category group** and **category**: name, hidden (kept, but the budget ignores it), position (new ones go to the
  end), note, internal. A category is deleted only into another, which takes over everything it has; a group only
  when it is empty ([ADR 0003](../DECISIONS.md)).
  Lookup keys of categories are not unique (an old "Urlaub" next to "🏖️ Urlaub"); groups have none. Each user's
  budget gets YNAB's internal group "Internal Master Category" with "Inflow: Ready to Assign" (UI "Zu verteilen")
  with its first use; internal ones are not listed, not editable and take no assignments or targets. Ready to
  Assign's lookup key is reserved: no other category takes it, and looking it up finds only Ready to Assign.
- **Names** usually start with an emoji ("🛒 Lebensmittel"), stored as entered. Lookups by name (MCP, search,
  suggestions, import) use the lookup key: Unicode NFC, without emoji and symbols (incl. ZWJ sequences, skin tones,
  keycaps, flags, variation selectors), whitespace collapsed, lower case, "ß" as "ss"; emoji-only names keep their
  emoji without variation selectors and skin tones ("❤️" = "❤", "👍🏽" = "👍"). They prefer regular payees
  over transfer payees, else report not found or ambiguous.
- **Amounts** are integer cents, at most 100 billion euros either way (10^13 cents) on transactions,
  subtransactions, assignments and targets.
- **Months** (assignment, target version, snooze) are stored as the first of the month; every function takes any day
  of it, as a date or ISO 8601 string.
- **Assignment**: category, month, amount (may be negative); one per category and month
- **Target version**: category, from month, cadence (monthly, by date, none = no target from then on), amount
  (positive), due on (by date only, not before from month), repeats yearly (by date only), set aside (YNAB
  `goal_needs_whole_amount`: "set aside another" vs. "refill up to"). A version applies until the next one, so
  changing a target keeps past months.
- **Target snooze**: category, month; one per category and month (snoozing again returns the one there is)
- **Transaction**: account, date, amount (signed), payee, category, memo, cleared (`uncleared`, `cleared`,
  `reconciled`; UI "Vorgemerkt", "Gebucht", "Abgeglichen"), approved (manual entries by default, imports not),
  transfer counterpart (a transaction, or for a split's transfer its subtransaction), source (`manual`, `ynab`,
  `file`, `bank`, `api`, `kasse`, `depot`: where it was created, set once; `api` from the former YNAB-compatible API, `kasse` a share of a Kasse expense, `depot` a value change), matched transaction (see match
  proposals), deleted at (soft delete; deleted transactions cannot be changed, only
  moved with their category into another). The register is what counts: transactions not deleted and no match
  proposal (`Ledger.in_register/1`).
- **Reconciled lock**: the Ledger refuses any change that alters a reconciled transaction ("ist abgeglichen"),
  leaving the reconciled state included, whether made on it directly or through a transfer: its counterpart's or a
  split's subtransaction's edit kept in step (amount, date, memo, account, category), released (payee no longer a
  transfer, subtransaction removed, turned into a split) or deleted with it. The caller passes
  `reconciled: :confirmed` to `update_transaction/4`, `delete_transaction/3`, `accept_match/3` or
  `recategorize/4` (deleting a category) after asking; the UI asks first.
- **Transfers**: a transaction or subtransaction is a transfer when its payee is a transfer payee; never to its own
  account, and a split is none as a whole. The Ledger alone creates and keeps the counterpart in the payee's
  account (amount negated, same date and memo, payee = the other account's transfer payee; cleared and approved per
  side), moves it when payee or account change and removes it when the payee stops being a transfer
  payee. Deleting either side deletes both, deleting a split deletes its subtransactions' counterparts; the
  counterpart of a subtransaction is changed and deleted in its split. Transfers to closed accounts are allowed.
- **Category rule**, checked by `Ledger.create_transaction/2` and `update_transaction/4` with all accounts
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
  dedupe ([ADR 0001](../DECISIONS.md)); origins move with their transaction to another account.
  Moving a transaction, or a counterpart, into an account that has one of its external ids from the same source
  already is refused.
- References are restricted: nothing that history points to can be deleted, except a category moved into another
  (ADR 0003). The contexts check references before
  writing, so a missing one is a validation error ("existiert nicht"), not a constraint error.
- **Bank balance**: account, source (`file`: a file's ledger balance, `bank`: bank sync), date, amount; one per
  account, source and date. Reconciling offers the latest.
- **Bank connection**: provider, bank, session id, valid until, linked accounts (provider account id → account),
  last sync, last error
- **User**, **passkey**, **user token** (`phx.gen.auth` plus passkeys, see Login)

Amounts are integers in cents.

## Budget rules

YNAB's math as it is today. The method is YNAB's too: every euro gets assigned, and overspending is dealt with. The UI
treats RTA > 0 and overspent categories as open tasks (Zu verteilen in green on the neutral month card, red Verfügbar on
overspent categories whose popover covers them from a picked source category), and RTA = 0 with nothing overspent as the
resting state.

- **Ready to Assign (RTA)** per month m, cumulative:
  RTA(m) = income up to and including m − assigned up to and including m − overspending of the months before m
- **Available** per category and month = max(available last month, 0) + assigned + activity; for the first month
  the carry is 0
- **Overspending** (negative available): shown red; the category starts the next month at 0 and the full amount
  is subtracted from that month's RTA. A negative available is never carried into the next month (YNAB 4 could).
  There are no credit cards, so YNAB's credit overspending and payment categories do not exist.
- Shown as "Zu verteilen" in a month: RTA(m) − assigned in later months (as YNAB's UI does; the API's
  `to_be_budgeted` is RTA(m) without that subtraction); the month card adds it up as YNAB 4 does: not assigned
  and overspent last month, income and assigned this month, assigned in future months (open months only)
- Both formulas reproduce YNAB's API numbers exactly (`to_be_budgeted`, category `balance`), checked against a
  real budget: every month and every category-month matched.
- **Assignments are never refused**, as in YNAB: RTA can go below zero through assignments or overspending; then
  it is red with the action "cover from categories".
- **Uncovered months**: while a later month's RTA is below zero, the month card warns which months are not covered
  and by how much ("November nicht gedeckt: es fehlen 300 €"), up to the last month with data or that changes RTA
  (the empty months after it only repeat it). Overspending only shows up in the next month's RTA, so the month card alone would not
  tell.
- Transactions in budget accounts without a category form an "uncategorised" row that carries and overspends
  like a category but takes no assignments
- Transfers between budget accounts have no category; transfers between a budget and a tracking account need one
- Income is what is categorised "Ready to Assign", the only income category; it is available in the month it is
  dated. Inflows to other categories (refunds) are valid and count as those categories' activity.
- Targets: only YNAB's **needed for spending** (`NEED`), the one type in use:
  - monthly amount, or amount by a date (spread over the months until then); after its month one that repeats
    yearly starts again, the others ask nothing
  - "set aside another" (`goal_needs_whole_amount` true: assigned this month counts) or "refill up to" (false:
    what is carried counts, plus what is assigned)
  - per category and month: underfunded amount, progress, snoozed (still underfunded, as YNAB's inspector and
    API show it, but left out of the month's total and of filling); auto-assign fills the underfunded categories
    (all, or the selected one) from RTA (in budget order, snoozed ones skipped, as far as RTA reaches without what
    later months have assigned, in a closed month too)
  - UI after YNAB: icons before Verfügbar in the table (clock, check, pause); the category dialog says the target
    and its status in sentences ("Erfüllt.", "Im Plan.", "Noch 13,99 € diesen Monat.", "Überzogen um 2,00 €.",
    "Pausiert im Oktober."), a bar only for a target by a date
  - other goal types (`TB`, `TBD`, `MF`, `DEBT`) only if needed later
- All of this is one pure module (`Abakus.Budget`) computed from assignments and transactions; months are not
  stored as snapshots. It computes every month from the first with data to the month after the last with data,
  where that month's overspending lands. Property tests plus hand-computed, fictional fixtures in YNAB's month
  format.

## Import

All imports land as unapproved, `cleared`, with an external id. A transaction is never imported twice from the
same source; across sources (and against manual entries) a match is proposed, never merged silently.

- **Bank sync** imports as the file import does: deduped by (account, source, external id) with the provider's
  transaction id, match proposals, nothing dated up to the account's newest reconciled transaction
- **Category suggestion**: the payee's last category
- **CSV import**: only if a bank needs it later.
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

## Tracking accounts

Only used for the portfolios (securities accounts and their cash accounts). Their value is booked by the Depot,
the way YNAB tools post market values:

- Each of the budget owner's portfolios is one tracking account fed by `portfolio`, opened with the portfolio
  (ADR 0017) and named after it; its register is the portfolio's tab Register, and the sidebar lists it only
  under Depots. An account fed by `portfolio` whose portfolio is gone is closed with its history, a last value
  change taking it to 0
- Money moving into a portfolio is a transfer from a budget account, categorised (e.g. savings) in Abakus: once the
  budget owner links the Depot to the budget under Einstellungen › Depots (start date, category for purchases;
  ADR 0018), each flow between a portfolio and a Verrechnungskonto that is a budget account is a linked transaction
  there, led by the Depot (`Abakus.Depot.BudgetLink`): purchases and cash moved into a portfolio's cash are outflows
  in that category, sales and cash moved back inflows to Ready to Assign, all transfers to the portfolio's account;
  dividends are inflows to Ready to Assign from the security. Depot transactions before the start date stay in the
  Depot only
- Every day after the price job, the Depot books the difference between the account's balance and the value of
  its portfolio, its cash included, as one transaction through the Ledger, payee "Wertänderung", approved and
  cleared, none without a difference, so a new account starts at the portfolio's value; another run that day
  amends that transaction instead of booking a second one. Only it (`Abakus.Depot.BudgetFeed`) and the linked
  transfers change the account, so the value change keeps the market movement, and it cannot be reconciled
- Each Verrechnungskonto has a role, set under Einstellungen › Depots: "ist Budgetkonto X" (the same bank account
  as a budget account; the budget owner's only, at most one per budget account), counting toward nothing
  else; "Cash von Depot Y" (cash at the broker of one of the user's portfolios), counting toward that portfolio's
  value and account and shown in its Bestand as „davon Cash“; or none. One without a role shows as a warning on
  Vermögen, linking to its setting
- A tracking account nothing feeds is adjusted by hand

## MCP

At `/mcp/<MCP_SECRET>` (off without the secret), interface in English, data as entered; access, protocol and tools in
[MCP.md](MCP.md) ([ADR 0012](../DECISIONS.md)).

- Kasse (since the move): `balances`, `balance_history`, `search_expenses`, `statistics`, `activity`, `schema`,
  `sql_query`; writes `create_expense` and `create_reimbursement`
- Budget, read (v2): `accounts` (balances, cleared, last reconciled), `budget` (RTA and per category for one or more months),
  `search_transactions`, `statistics` (spending by category, payee, month; previous year comparison),
  `schema`, `sql_query` (`SELECT`/`WITH`, ≤ 500 rows, 2 s)
- Budget, write (v2): `create_transaction` (unapproved, so it shows up for review). Nothing is changed or deleted via MCP.

## Screens

- **Budget**: multi-month view
- **Konten**: the register of all accounts (the sidebar's Alle Konten) and of each account, reconcile;
  "Konto hinzufügen" in Alle Konten
- **Buchung**: transaction form (FAB on phones)
- **Import & Sync**: tabs Bankdateien (file import with preview; the budget owner's) and Belege (the receipt
  inbox and the PDF upload, its count on the tab and the sidebar entry; users with a portfolio); later bank
  connections with consent expiry
- **Kasse**: Ausgaben (list, search, the expense form), Salden with the settlement and Aktivität
- **Vermögen and Depots** (Finanzen): Vermögen (net worth: for the budget owner all budget and tracking accounts
  but those closed with money left in them, its curve showing the Depot's value before the budget's first
  transaction, for anyone else their portfolios and Verrechnungskonten, optionally against the benchmark) and
  Depots, for all portfolios or one, with „Buchung erfassen“ and the tabs Bestand (holdings and
  Verrechnungskonten), for one portfolio of the budget owner Register (its account's register),
  Buchungen, Dividenden, Performance and, for all portfolios, Wertpapiere (prices, quote feeds, the benchmark,
  exchange rates); a page per security
- **Einstellungen**: a mode of the sidebar under `/settings/…`, with the way back to the area used last and the
  sections grouped by area; each group shows only to users of its area, whose settings answer 404 to others.
  Allgemein: Zugang (passkeys, email), Aussehen (theme, per device). Kasse: Gruppe (the group's name), Teilnehmer
  (adding one invites their user), Kategorien, Wiederkehrende Ausgaben, Wechselkurse, Budget-Verknüpfung (the budget
  owner's only: switching the link on, its account and which budget category each Kasse category's shares land in)
  and Export (CSV/JSON). Depot, for everyone, so anyone may start one: Depots (the user's portfolios and
  Verrechnungskonten with their roles, and for the budget owner the link to the budget) and Belegeingang
  (Paperless-ngx and the receipt recognition; users with a portfolio).
  Categories and groups are edited in the budget

State that should survive a reload (screen, month, account, filters) lives in the URL; the number of months
follows the window.

## Phases

### v1 — switch from YNAB

1. Skeleton: Phoenix, SQLite, UI components, login with magic link and passkeys, PWA manifest,
   container, deploy behind a reverse proxy, CI (format, credo, tests, assets)
2. Domain and `Abakus.Budget` incl. targets, with property tests
3. Budget view, desktop and phone
4. Accounts, register, transaction form, splits, transfers, reconcile
5. OFX/QFX import with matching and approval
6. The shared expenses move into Abakus and are linked to the budget (#43)
7. The portfolios move into Abakus as the Depot and book their value into the tracking accounts (#44)

Acceptance: every month shows the same RTA and the same assigned, activity, available and underfunded per category
as YNAB would for the same data; an OFX/QFX export imports without duplicates; the shared expenses reach the budget
without a sync.

### v2 — bank sync and MCP

Enable Banking connections, scheduled sync, consent reminders by mail, bank balance in reconcile; the budget's MCP tools.

### v3 — offline entry

Only offline entry: a queue in the PWA that creates transactions while offline and sends them when back online
(create only, no edits, so no conflicts). Nothing else is planned for v3; scheduled transactions stay out.

## Operations

- One container; all data (the SQLite database) lives in the data volume at `/app/data`; every night at 03:00 a
  copy (`VACUUM INTO`) goes to `/app/data/backups`, the newest seven are kept; copies elsewhere are the
  operator's job. The Depot's receipt files live in `receipts/` next to the database, in the data volume but
  outside the nightly backup
- Jobs in the release: the ECB rates (daily at 17:00), recurring expenses (hourly), the Depot's prices and
  DivvyDiary data (daily at 18:00), each user's Paperless (every 15 minutes) and the backup, at the host's local
  time (`TZ`, `Europe/Berlin` in the image); `jobs: false` turns them off in tests
- Runs behind the operator's HTTPS reverse proxy, which sets `X-Forwarded-Proto`
- Config via env: `PHX_HOST` (required: the public host, also the passkey relying party id), `SECRET_KEY_BASE`,
  SMTP, `MCP_SECRET`, `MCP_ALLOWED_CIDRS`, `TRUSTED_PROXIES`, `DIVVYDIARY_API_KEY`
  (the Depot's countries, sectors and dividends; optional), `RECEIPT_MODEL_URL`, `RECEIPT_MODEL`,
  `RECEIPT_MODEL_KEY`, `RECEIPT_MODEL_THINKING` (the Depot's receipt recognition; optional),
  `ENABLE_BANKING_APP_ID` and the private key as a read-only mounted file (v2)
- `/up` checks the DB and, from v2, that no bank connection has failed for more than a day

## Open

- How YNAB computes `goal_under_funded` for targets by a date in detail (Abakus rounds up to the cent), and what
  it reports after the date of one that does not repeat (Abakus asks nothing then)
- Which banks show up in Enable Banking's restricted mode and their `maximum_consent_validity` (needs the
  owner's Enable Banking account)

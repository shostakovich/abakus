# CLAUDE.md – Abakus

Self-hosted envelope budgeting; scope, domain and phases in [`docs/SPEC.md`](docs/SPEC.md), UI direction in
[`docs/UI.md`](docs/UI.md). UI text is German; code, comments and docs English, sparse comments.

Domain terms are in [`CONTEXT.md`](CONTEXT.md) (use them in code), decisions in [`DECISIONS.md`](DECISIONS.md).

## Validation

```
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
```

CI runs the same plus `mix assets.deploy`. Erlang/Elixir versions: `.tool-versions`.

## Conventions

- Schemas `use Abakus.Schema` (`:utc_datetime_usec` timestamps). Migrations are recorded in production: add new
  ones, leave old ones as they are; releases run them via `Abakus.Release.migrate/0`.
- DB tests run synchronously with `pool_size: 1` (SQLite is busy otherwise).
- UI: Setzkasten components and conventions (Setzkasten's `guides/design-system.md`). App CSS only for domain
  UI, on theme tokens, in the partials under `assets/css/`. A Setzkasten bug or gap is fixed in
  `shostakovich/setzkasten`, not worked around in the app.
- Theme (light, dark, system) and the collapsed sidebar are per device: `localStorage["setzkasten:theme"]` and
  `["setzkasten:sidebar"]`, applied before paint by `<.theme_script>` in the root layout. So are the register's memo
  column and the budget's calculation (`["abakus:register-memo"]`, `["abakus:budget-calculation"]`), set on `<html>`
  before paint as `data-register-memo` and `data-budget-calculation` by the root layout's own nonce'd script.
- Confirmations go through Setzkasten's confirm dialog (`confirm` on buttons, menu items and list row actions);
  tests drive it with `Setzkasten.Test.Confirm`.
- Sign-in lives in `Abakus.Users` (`User`, `UserToken`, `Passkey`, `Scope`, `UserNotifier`) and
  `AbakusWeb.UserAuth`. "Account" means a bank account, so nothing about users is called account.
- Passkeys (`Abakus.WebAuthn`) check origin and RP ID from the endpoint URL, so they work on `localhost` and the
  configured public host (`PHX_HOST`), not on a LAN IP. Every check has a breaking test in
  `test/abakus/web_authn_test.exs` using `FakeAuthenticator`; a new check gets one too.
- Every page needs a session; `test/abakus_web/router_test.exs` lists the public ones. The CSP allows no inline
  script without `nonce={@csp_nonce}` and no inline `style` attributes.
- Amounts in every area: `Abakus.Money` reads what is typed (`parse/2`, the Depot's `parse_number/1`) and writes
  field values (`amount/2`; the Depot's numbers `Abakus.Format.decimal/2`; both read back unchanged) and shown
  amounts (`euros/2`, `money/2`). MCP output and CSV exports keep their own formats. Dates, times, counts,
  percentages and other numbers are written by `Abakus.Format` (on `Setzkasten.Format`); what only the Depot shows,
  such as prices, fund sizes and TERs, by `AbakusWeb.Depot.Format`.
- The Kasse (`Abakus.Kasse`, `AbakusWeb.Kasse`, tables `kasse_…`): money is integer cents, local time is the
  host's `TZ` (`Abakus.LocalTime`, no time zone database). Its jobs and the backup run in the release;
  `config/test.exs` turns them off (`jobs: false`). What the app, MCP, jobs and tasks call takes `%Scope{}`
  (ADR 0019): a person's, or `Scope.system()` for jobs, tasks and MCP reads; `Abakus.Kasse.Access` refuses any
  other, except in what the budget calls of the budget link (`recategorize/3`, `expense_ids/2`), which
  takes a plain user scope. The budget link acts for the scope's person. Tests get a person's scope with
  `scope_of/1` from `Abakus.KasseFixtures`.
- The budget: `Abakus.Ledger`, `Abakus.Categories`, `Abakus.FileImport` and the import core it shares with bank
  sync, `Abakus.Import` (keyed by source), take `%Scope{}` and see only the rows with the user's `user_id` (ADR
  0019); each user's Ready to Assign comes with its first use. What writes into it from another area writes with the
  budget owner's user, whichever way it gets that scope: the Depot's budget feed (`Scope.for_budget_owner/0`) and
  link (the caller's) and the Kasse's budget link (the linked person's, `Scope.for_participant/1`). Tests get the
  owner's scope with `budget_scope/0` from `Abakus.DomainFixtures`.
- Bank sync (`Abakus.BankSync`, `AbakusWeb.BankConnectionsLive`, tables `bank_connections`, `bank_linked_accounts`,
  `bank_sync_runs`) is the budget owner's alone: what takes a scope raises `Abakus.BankSync.AccessError` for any
  other, except the health check's `failing?/1`, which takes the system's alone; it imports through `Abakus.Import`
  with the owner's scope, its job (`Abakus.BankSync.Job`) at 06:00 and 18:00; consents about to end show a banner
  in Finanzen (`AbakusWeb.BankConsents`, passed to the layout). Its Enable Banking client is a
  behaviour; tests swap it for `Abakus.BankSync.FakeClient`, which is not configured until `serve/1` starts it,
  serves what `put_transactions/2` and `put_balances/2` give it and records `fetches/0`, and connect with
  `connection_fixture/0` from `Abakus.BankSyncFixtures`.
- Exchange rates (`Abakus.ExchangeRates`, tables `exchange_rates`, `exchange_rate_runs`) are shared: one daily job
  loads the ECB rates, each area looks them up by its own rule, manual rates are the Kasse's only; its rule and the
  logged changes to manual rates live in `Abakus.Kasse.Rates`. Tests swap the source in `config/test.exs`
  (`Abakus.FakeExchangeRateSource`).
- The Depot (`Abakus.Depot`, `AbakusWeb.Depot`, tables `depot_…`): context functions take `%Scope{}` and see only
  the user's own data, except securities, prices and compositions, which all share. Outside
  services are behaviours swapped in `config/test.exs` (`Abakus.Depot.Fake…`); `:pdftotext` tests need poppler.
  Receipt files live in `receipts/` next to the database. Only `Abakus.Depot.BudgetFeed` (value changes) and
  `Abakus.Depot.BudgetLink` (transfers) write to accounts fed by `portfolio`.
- MCP (`Abakus.MCP`, `AbakusWeb.MCPPlug`, docs/MCP.md) lives outside the sign-in at `/mcp/<MCP_SECRET>`; tests go
  through `AbakusWeb.MCPCase`.
- Dependencies: few and mature, each with a reason.

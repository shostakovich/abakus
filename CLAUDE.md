# CLAUDE.md – Abakus

Self-hosted envelope budgeting; UI direction in [`docs/UI.md`](docs/UI.md). UI text is German; code, comments and
docs English, sparse comments.

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
- Confirmations go through Setzkasten's confirm dialog; tests drive it with `Setzkasten.Test.Confirm`.
- "Account" means a bank account, so nothing about users is called account.
- Every passkey check has a breaking test in `test/abakus/web_authn_test.exs`; a new check gets one too.
- Every page needs a session; `test/abakus_web/router_test.exs` lists the public ones. The CSP allows no inline
  script without `nonce={@csp_nonce}` and no inline `style` attributes.
- Amounts are read and written by `Abakus.Money`; dates, times, counts and other numbers by `Abakus.Format`.
- Context functions take `%Scope{}` and see only the user's rows (ADR 0019); jobs, tasks and MCP reads use
  `Scope.system()`.
- Local time is the host's `TZ` through `Abakus.LocalTime` (no time zone database).
- Outside services are behaviours swapped for fakes in `config/test.exs`, where the jobs are off.
- Dependencies: few and mature, each with a reason.

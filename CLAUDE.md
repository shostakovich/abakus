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
  `["setzkasten:sidebar"]`, applied before paint by `<.theme_script>` in the root layout.
- Confirmations go through Setzkasten's confirm dialog (`confirm` on buttons, menu items and list row actions);
  tests drive it with `Setzkasten.Test.Confirm`.
- Sign-in lives in `Abakus.Users` (`User`, `UserToken`, `Passkey`, `Scope`, `UserNotifier`) and
  `AbakusWeb.UserAuth`. "Account" means a bank account, so nothing about users is called account.
- Passkeys (`Abakus.WebAuthn`) check origin and RP ID from the endpoint URL, so they work on `localhost` and the
  configured public host (`PHX_HOST`), not on a LAN IP. Every check has a breaking test in
  `test/abakus/web_authn_test.exs` using `FakeAuthenticator`; a new check gets one too.
- Every page needs a session; `test/abakus_web/router_test.exs` lists the public ones. The CSP allows no inline
  script without `nonce={@csp_nonce}` and no inline `style` attributes.
- Dependencies: few and mature, each with a reason.

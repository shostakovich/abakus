# CLAUDE.md – Abakus

Self-hosted envelope budgeting; scope, domain and phases in [`docs/SPEC.md`](docs/SPEC.md), UI direction in
[`docs/UI.md`](docs/UI.md), `mockup/` is the click dummy. UI text is German; code, comments and docs English,
sparse comments.

Domain terms are in [`CONTEXT.md`](CONTEXT.md) (use them in code), decisions in `docs/adr/`.

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
- UI: felt-css (clean look) with Bootstrap class names via `core_components`. A felt.css bug becomes an issue in
  `shostakovich/felt-css`, the app keeps plain Bootstrap markup.
- Theme (light, dark, auto) is per device: `localStorage.theme`, applied by `#theme-script` in the root layout.
- Dependencies: few and mature, each with a reason.

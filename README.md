# Abakus

Self-hosted envelope budgeting for one household: YNAB's budgeting rules, a multi-month budget view like
[Actual Budget](https://actualbudget.org/), reconciling, OFX/QFX import, bank sync and a YNAB-compatible API. It is
meant to replace YNAB for my own use. **The user interface is German.**

## Status

Planning. Nothing to install yet.

- [docs/SPEC.md](docs/SPEC.md): scope, budget rules, import, API, phases
- `mockup/`: click dummy with example data, built with [felt-css](https://felt-css.rocu.de/)

```sh
python3 -m http.server 8078 --directory mockup
```

## Before you use this

- This is a personal project, built for my own household (one budget, 1–2 people, EUR).
- I don't accept pull requests (benevolent dictator and all that), but forks are very welcome.

## Planned stack

Elixir, Phoenix LiveView, SQLite, felt-css; one container behind a reverse proxy.

## License

Public domain ([The Unlicense](LICENSE)). Bank sync follows Actual Budget's Enable Banking integration (MIT).

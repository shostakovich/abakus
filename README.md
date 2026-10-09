# Abakus

Self-hosted envelope budgeting for one household: YNAB's budgeting rules, a multi-month budget view like
[Actual Budget](https://actualbudget.org/), reconciling, OFX/QFX import, bank sync and a YNAB-compatible API. It is
meant to replace YNAB for my own use. **The user interface is German.**

## Status

Skeleton: Phoenix app, container and CI. No budget features yet.

- [docs/SPEC.md](docs/SPEC.md): scope, budget rules, import, API, phases
- `mockup/`: click dummy with example data, built with [felt-css](https://felt-css.rocu.de/)

## Development

Elixir and Erlang as in `.tool-versions`.

```sh
mix setup
mix phx.server
```

Then open http://localhost:4000.

Click dummy:

```sh
python3 -m http.server 8078 --directory mockup
```

## Deploy

- Image: `ghcr.io/shostakovich/abakus`; `docker-compose.yml` is an example.
- Required environment: `PHX_HOST` (the public host name) and `SECRET_KEY_BASE` (`openssl rand -hex 64`).
- Before the first start: `mkdir data && chown 1000:1000 data`; the database lives there.
- A reverse proxy must terminate HTTPS and send `X-Forwarded-Proto: https`. Plain HTTP still serves pages, but
  the live UI only connects from `https://$PHX_HOST`.
- `/up` answers 200 while the app and its database are up, for health checks.

## Before you use this

- This is a personal project, built for my own household (one budget, 1–2 people, EUR).
- I don't accept pull requests (benevolent dictator and all that), but forks are very welcome.

## Stack

Elixir, Phoenix LiveView, SQLite, felt-css; one container behind a reverse proxy.

## License

Public domain ([The Unlicense](LICENSE)). Bank sync follows Actual Budget's Enable Banking integration (MIT).

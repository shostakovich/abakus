# Abakus

Self-hosted envelope budgeting for one household: YNAB's budgeting rules, a multi-month budget view like
[Actual Budget](https://actualbudget.org/), reconciling, OFX/QFX import, bank sync and a YNAB-compatible API. It is
meant to replace YNAB for my own use. **The user interface is German.**

## Status

Sign-in with magic link and passkeys, the budget math, the YNAB import, the budget view on desktop, the account
list, the register, where transactions are edited in place as in YNAB, reconciling, the OFX/QFX file import with
match proposals, the YNAB-compatible API with its tokens and the settings. What remains of v1 is switching the
existing YNAB API clients over to Abakus; bank sync and MCP follow in v2.

- [docs/SPEC.md](docs/SPEC.md): scope, budget rules, import, API, phases
- `mockup/`: click dummy with example data, built with [felt-css](https://felt-css.rocu.de/)

## Development

Elixir and Erlang as in `.tool-versions`.

```sh
mix setup
mix phx.server
```

Then open http://localhost:4000 (passkeys need `localhost`, not `127.0.0.1` or a LAN IP).

Every page needs a sign-in and there is no sign-up, so invite the first user. In development the mails stay in
the server's mailbox at http://localhost:4000/dev/mailbox, so invite from the running server:

```sh
iex -S mix phx.server
iex> Abakus.Users.invite_user("you@example.com", &AbakusWeb.UserAuth.magic_link_url/1)
```

`mix abakus.invite you@example.com` works as well and prints the sign-in link, since its mail does not reach
the server's mailbox. After signing in, add a passkey under Einstellungen.

Click dummy:

```sh
python3 -m http.server 8078 --directory mockup
```

## Deploy

- Image: `ghcr.io/shostakovich/abakus`; `docker-compose.yml` is an example.
- Required environment: `PHX_HOST` (the public host name) and `SECRET_KEY_BASE` (`openssl rand -hex 64`).
- Mail for sign-in links: `SMTP_HOST`, `SMTP_PORT` (465 for TLS, otherwise STARTTLS), `SMTP_USERNAME`,
  `SMTP_PASSWORD` and `MAIL_FROM`.
- Before the first start: `mkdir data && chown 1000:1000 data`; the database lives there.
- A reverse proxy must terminate HTTPS and send `X-Forwarded-Proto: https`. Plain HTTP still serves pages, but
  the live UI only connects from `https://$PHX_HOST`.
- `/up` answers 200 while the app and its database are up, for health checks.

Invite the first user with

```sh
docker compose exec abakus bin/abakus eval 'Abakus.Release.invite("you@example.com")'
```

They get a sign-in link by mail (valid 15 minutes) and add a passkey under Einstellungen.

Import the budget from YNAB with a personal access token (YNAB: Account Settings → Developer Settings), passed to
this one command only. It replaces the whole budget, so it refuses once Abakus holds transactions of its own, and
then checks every month, category and account against YNAB's numbers (exit code 1 on a difference):

```sh
docker compose exec -e YNAB_TOKEN=… abakus bin/abakus eval 'Abakus.Release.import_ynab()'
```

With several plans in YNAB it lists them; pass the id as `import_ynab("…")`. Locally: `mix abakus.ynab_import`.

## Before you use this

- This is a personal project, built for my own household (one budget, 1–2 people, EUR).
- I don't accept pull requests (benevolent dictator and all that), but forks are very welcome.

## Stack

Elixir, Phoenix LiveView, SQLite, felt-css; one container behind a reverse proxy.

## License

Public domain ([The Unlicense](LICENSE)). Bank sync follows Actual Budget's Enable Banking integration (MIT).

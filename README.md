# Abakus

Self-hosted envelope budgeting for one household: YNAB's budgeting rules, a multi-month budget view like
[Actual Budget](https://actualbudget.org/), reconciling, OFX/QFX import and bank sync. It is
meant to replace YNAB for my own use. **The user interface is German.**

## Status

Sign-in with magic link and passkeys, the budget math, the budget view on desktop with its month calculation,
category dialog (targets), auto-assign and covering and moving money, the register for one account or all of them,
where transactions are edited in place as in YNAB, reconciling, the OFX/QFX file import with match proposals and the
settings, and the Kasse: the household's shared expenses with their balances, activity log, recurring expenses,
categories, exchange rates, CSV/JSON export, its MCP server for AI assistants and the link that books the budget
owner's shares in the budget; and the Depot, part of the area Finanzen with the budget: each user's Vermögen and
portfolios with holdings, dividends, transactions, performance and securities, whose prices come from Yahoo every
evening, a receipt inbox that reads bank PDFs, uploaded or taken from Paperless-ngx, each of the budget owner's
portfolios as a tracking account with its daily value change, and the Verrechnungskonten as accounts that the Depot
transactions book their cash into, budget accounts once the Depot is linked to the budget. Bank sync and the budget's
MCP tools follow in v2.

- [docs/SPEC.md](docs/SPEC.md): scope, budget rules, import, phases
- [docs/MCP.md](docs/MCP.md): the MCP server, its access rules and tools

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
the server's mailbox. The first user owns the budget. After signing in, add a passkey under Einstellungen.

The Kasse is for its participants only, so add yourself as the first one; more can then be added under
Einstellungen › Kasse › Teilnehmer, which invites them by mail:

```sh
mix abakus.add_participant you@example.com "Your name"
```

Each user's Depot opens once they create a portfolio under Einstellungen › Depot › Depots.

## Deploy

- Image: `ghcr.io/shostakovich/abakus`; `docker-compose.yml` is an example.
- Required environment: `PHX_HOST` (the public host name) and `SECRET_KEY_BASE` (`openssl rand -hex 64`).
- Mail for sign-in links: `SMTP_HOST`, `SMTP_PORT` (465 for TLS, otherwise STARTTLS), `SMTP_USERNAME`,
  `SMTP_PASSWORD` and `MAIL_FROM`.
- Before the first start: `mkdir data && chown 1000:1000 data`; the database lives there.
- A reverse proxy must terminate HTTPS and send `X-Forwarded-Proto: https`. Plain HTTP still serves pages, but
  the live UI only connects from `https://$PHX_HOST`.
- `/up` answers 200 while the app and its database are up, for health checks.
- Every night at 03:00 a copy of the database goes to `data/backups` (mode 0600); the newest seven are kept.
- `TZ` (default `Europe/Berlin`) is the local time of "today" in every area, of the Kasse's dates and of the jobs:
  ECB rates at 17:00, recurring expenses hourly, the Depot's prices at 18:00, the backup.
- `DIVVYDIARY_API_KEY` (optional) brings the Depot's countries, sectors and dividend dates from DivvyDiary.
- The Depot's receipt recognition (optional): any OpenAI-compatible chat API such as Ollama with
  `RECEIPT_MODEL_URL` (e.g. `http://localhost:11434/v1`), `RECEIPT_MODEL` and, if the API wants one,
  `RECEIPT_MODEL_KEY`; `RECEIPT_MODEL_THINKING=on` lets the model think. The text comes from Paperless or else from
  `pdftotext`. Without a model a receipt opens an empty form. Receipt PDFs live in `data/receipts`, next to the
  database, outside the nightly backup. Each user enters their Paperless-ngx under Einstellungen → Belegeingang;
  it is polled every 15 minutes.
- MCP ([docs/MCP.md](docs/MCP.md)): `MCP_SECRET` (empty turns it off; the endpoint is `/mcp/<MCP_SECRET>`),
  `MCP_ALLOWED_CIDRS` (who may call it, default `160.79.104.0/21`) and `TRUSTED_PROXIES` (proxies whose
  `X-Forwarded-For` counts).

Invite the first user with

```sh
docker compose exec abakus bin/abakus eval 'Abakus.Release.invite("you@example.com")'
```

They get a sign-in link by mail (valid 15 minutes), own the budget and add a passkey under Einstellungen. The
first participant of the Kasse, who invites the others from there:

```sh
docker compose exec abakus bin/abakus eval 'Abakus.Release.add_participant("you@example.com", "Your name")'
```

## Before you use this

- This is a personal project, built for my own household (one budget, 1–2 people, EUR).
- I don't accept pull requests (benevolent dictator and all that), but forks are very welcome.

## Stack

Elixir, Phoenix LiveView, SQLite, Tailwind CSS and daisyUI with [Setzkasten](https://github.com/shostakovich/setzkasten);
one container behind a reverse proxy.

## License

Public domain ([The Unlicense](LICENSE)). Bank sync follows Actual Budget's Enable Banking integration (MIT). The
Lucide icons in `assets/vendor/lucide` are under the ISC License (some derive from Feather, MIT), both in its
`LICENSE`; the plush images and app icons in `priv/static/images` were made for Zipfelkasse and Abakus. Chart.js
in `assets/vendor` is under the MIT License.

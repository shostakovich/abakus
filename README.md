# Abakus

Self-hosted envelope budgeting for one household, meant to replace YNAB for my own use. **The UI is German.**

- **Budget:** YNAB's rules in a multi-month view like [Actual Budget](https://actualbudget.org/), targets, an
  editable register, reconciling, OFX/QFX import and bank sync through [Enable Banking](https://enablebanking.com/),
  both with match proposals.
- **Kasse:** the household's shared expenses with balances, recurring expenses, exchange rates, export and an MCP
  server ([docs/MCP.md](docs/MCP.md)). They write into the budget owner's accounts.
- **Depot:** portfolios with holdings, dividends and performance, prices from Yahoo, and a receipt inbox for bank
  PDFs. Transactions write their cash into the accounts. Vermögen is the money in all accounts plus the securities.

## Development

Elixir and Erlang as in `.tool-versions`.

```sh
mix setup
iex -S mix phx.server
iex> Abakus.Users.invite_user("you@example.com", &AbakusWeb.UserAuth.magic_link_url/1)
```

Open http://localhost:4000 (passkeys need `localhost`); the sign-in mail is at http://localhost:4000/dev/mailbox.
The first user owns the budget. `mix abakus.add_participant you@example.com "Your name"` adds the first person to
the Kasse.

## Deploy

- Image `ghcr.io/shostakovich/abakus`; `docker-compose.yml` is an example. The database lives in `data/`
  (`chown 1000:1000 data`), with a nightly backup in `data/backups`.
- Required: `PHX_HOST`, `SECRET_KEY_BASE` (`openssl rand -hex 64`), and for sign-in mail `SMTP_HOST`, `SMTP_PORT`
  (465 for TLS, else STARTTLS), `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM`.
- A reverse proxy terminates HTTPS and sends `X-Forwarded-Proto: https`. `/up` is the health check.
- `TZ` (default `Europe/Berlin`) sets "today" and when the jobs run.
- Optional: `DIVVYDIARY_API_KEY` for countries, sectors and dividend dates; `RECEIPT_MODEL_URL`, `RECEIPT_MODEL`,
  `RECEIPT_MODEL_KEY`, `RECEIPT_MODEL_THINKING` for receipt recognition with an OpenAI-compatible API;
  `MCP_SECRET`, `MCP_ALLOWED_CIDRS`, `TRUSTED_PROXIES` for MCP; `ENABLE_BANKING_APP_ID`, `ENABLE_BANKING_KEY_FILE`
  (path of the application's private key) for bank sync.

```sh
docker compose exec abakus bin/abakus eval 'Abakus.Release.invite("you@example.com")'
docker compose exec abakus bin/abakus eval 'Abakus.Release.add_participant("you@example.com", "Your name")'
```

## Before you use this

A personal project for my own household (one budget, 1–2 people, EUR). I don't accept pull requests, but forks are
very welcome.

## Stack and license

Elixir, Phoenix LiveView, SQLite and [Setzkasten](https://github.com/shostakovich/setzkasten). Public domain
([The Unlicense](LICENSE)). Bank sync follows Actual Budget's Enable Banking integration (MIT). Lucide icons (ISC, partly Feather, MIT) and Chart.js (MIT) in `assets/vendor`; the plush
images in `priv/static/images` were made for Zipfelkasse and Abakus.

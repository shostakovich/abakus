# Abakus

Self-hosted envelope budgeting for one household, meant to replace YNAB for my own use. **The user interface is
German.**

## Development

```sh
mix setup
mix phx.server
```

## Deploy

See `docker-compose.yml`.

## Before you use this

A personal project for my own household. I don't accept pull requests, but forks are very welcome.

## License

Public domain ([The Unlicense](LICENSE)). Bank sync follows Actual Budget's Enable Banking integration (MIT). The
Lucide icons in `assets/vendor/lucide` are under the ISC License (some derive from Feather, MIT), both in its
`LICENSE`; the plush images and app icons in `priv/static/images` were made for Zipfelkasse and Abakus. Chart.js
in `assets/vendor` is under the MIT License.

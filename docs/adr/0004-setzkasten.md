## 0004. The UI moves to Setzkasten

Accepted, 2026-10-13. Replaces felt-css with Bootstrap class names.

- **Context:** Abakus was built on felt-css (clean look) with Bootstrap markup from `core_components`. The owner's
  other apps share Setzkasten, a Phoenix component library on Tailwind CSS 4 and daisyUI 5 with its own design
  rules, tokens, themes and app shell. Two visual systems mean twice the upkeep and two ways to build a screen.
- **Decision:** Abakus uses Setzkasten for its shell, components, themes and conventions; felt-css, its CDN link
  and CSP entries, the Bootstrap classes and the click dummy in `mockup/` are gone. Lucide icons live in
  `assets/vendor/lucide`.
- **Consequences:**
  - Domain UI (budget grid, month strip, register grid, reconcile) stays app CSS in the partials under
    `assets/css/`, written on Setzkasten's tokens.
  - A Setzkasten bug or missing piece is fixed upstream in `shostakovich/setzkasten`, not worked around in the app.
  - Confirmations use Setzkasten's confirm dialog instead of `data-confirm`.
  - Stored theme and sidebar choices reset once: Setzkasten keeps them under `setzkasten:theme` and
    `setzkasten:sidebar`.

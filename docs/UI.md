# UI direction

Abakus should feel familiar to someone coming from YNAB 4, today's YNAB and Actual Budget: same structure, same
vocabulary, same interaction patterns. The visual language is Setzkasten's (flat pages, one
accent, hairlines, tabular numbers), not a new design. Take the best of each app.

References are public: Actual's demo (https://demo.actualbudget.org/budget), screenshots of YNAB 4 and today's
YNAB from the web and YNAB's help center. No screenshots of real budgets in this repo.

## From YNAB 4

- One month on phones

## From today's YNAB

- Sidebar: bank connections

## Decisions after review round 1

- On phones Zu verteilen lives in a sticky month header; tapping a category opens its sheet (assignment, target,
  auto-assign, rename)

## Budget without inspector (as Actual)

- No inspector column and no filters: overspent categories show Verfügbar in red, its popover covers them
- No income group: income shows only in the month card's calculation
- A category row shows a pencil on hover and focus; it and the name open the category's dialog: name, target and
  deleting (the phone sheet shows the same parts after Verfügbar and auto-assign)
- Zugewiesen and Aktivität of a category stay blank at 0 (the assign field stays editable); Verfügbar 0 shows
  muted; group rows and the totals show 0,00
- Verfügbar has no pills: red when overspent, amber with a clock while the target is underfunded (only in months
  being budgeted: the current one and any other with money assigned; elsewhere plain), a green check before a
  funded target's number, a grey pause while snoozed, else plain; hovered like an editable cell, it opens the
  popover (cover, move, "Kategorie bearbeiten") for its month, which becomes the focus
- The category's dialog renames in place (Enter and leaving the field save, Escape puts the name back) and says
  the target in one sentence ("Jeden Monat auffüllen bis 650,00 €") with one status sentence: "Erfüllt.", "Im
  Plan." (by a date), "Noch 68,34 € diesen Monat." (with Zuweisen), "Überzogen um 180,20 €.", "Pausiert im
  Oktober."; only a target by a date has a bar (saved of its amount); spending a funded target leaves it funded
- A month card is a neutral card (surface and hairline): the month and a ghost ⋮ ("Verteilen"), then, centred,
  "Zu verteilen" with a chevron above the big amount (green above zero, red below, plain at zero; a past month:
  "Nicht verteilt am Monatsende", muted); no popover
- Verteilen (⋮): "Unterfinanzierte füllen (68,34 €)" with the month's underfunded total (only while something is
  underfunded and money is free), "In eine Kategorie …", "Zuweisung zurücksetzen"
- Zu verteilen shows and hides YNAB 4's calculation in every shown month at once, per device (collapsed by
  default): between the month and Zu verteilen, on a base-200 band between hairlines, the amount right-aligned in
  its column, then the text: "5.947,86 € Nicht verteilt im Sep", "0,00 € Überzogen im Sep", "+255,00 € Einnahmen
  im Okt", "−5.915,41 € Zugewiesen im Okt", "Für spätere Monate" when not zero in an open month, then in red the
  later months it does not cover ("−300,00 € Nicht gedeckt im Nov")
- On phones the sticky month header has the same parts in the same order, compact: the month with ‹ › and ⋮, the
  calculation, Zu verteilen
- Months follow the budget's width: two from 760 px (a window of about 1100 px with the sidebar), three from
  1110 px (about 1450 px); the category column takes 22 % (224–320 px), the months the rest

## Register

- The header in three rows split by hairlines, as in today's YNAB: the account's name with its kind and last
  reconcile and its actions (pencil, "Abgleichen", the page's only primary button); the balances, "Gebucht +
  Vorgemerkt = Arbeitssaldo"; the toolbar with "Buchung", "Datei-Import" and "Alle bestätigen" with its count,
  then "Ansicht" and the search. Phones: the balances in one line, search and "Ansicht", "Buchung" as the "+"
- Fixed columns, so an opened row keeps every column in place; the memo is a column of its own, narrower in narrow
  windows and hidden per device from "Ansicht"; the column header sticks while the list scrolls
- The cleared state as in Actual, in the last column: an empty circle (vorgemerkt), a checked one (gebucht), the
  lock (abgeglichen)

## Icons

Setzkasten's rule: plush images (`AbakusWeb.Plush`, one WebP per motif in `priv/static/images/plush`) for the
sidebar, dock and area switch, the settings hub, empty-state figures, Kasse categories, Depot booking rows and
portfolio rows; Lucide for actions, status, warnings and chevrons. In the sidebar accounts show the
emoji of their name, one without the plush of `AbakusWeb.AccountMotif` (receipt when the Kasse feeds it,
briefcase for a portfolio's, else by kind: landmark, piggy-bank, banknote, trending-up); a portfolio without emoji
shows the briefcase. One motif per meaning, e.g. wallet for the budget and cash bookings, landmark for accounts,
briefcase for portfolios and holdings, layers for securities and their trades, coins for dividends and interest,
file-text for receipts, clipboard-list for the empty booking list.

## Method

Every euro gets assigned and overspending is dealt with: RTA > 0 and overspent categories are open tasks, RTA =
0 with nothing overspent is the resting state.

## Review

Two art-director subagents rate every screen 1–10 with concrete feedback, per theme (light, dark), desktop (3, 2, 1 months) and phone (390 px):

- AD A, material/craft: Setzkasten fit, typography, spacing, numbers, details
- AD B, UI/product: hierarchy, familiarity for YNAB/Actual users, task flow, mobile, dark contrast

Both get the reference screenshots and the brief "steal the best from all three".

Round 1 is exploration, not polish: avoid a local maximum. The ADs say what is missing, what the references do
better, and where the screens should ideally go (direction, bigger structural changes, alternatives worth
trying), with a first score only as a baseline. The direction is agreed before polishing. From round 2 they rate
and say what is missing for 9.5. After every round the owner gets a score table with the history. Stop at 9.5.

Status 2026-10-08: seven rounds, both ADs at 9.5 or higher on every screen in light and dark (desktop 1100–1920
with full and collapsed sidebar, phone 390 px).

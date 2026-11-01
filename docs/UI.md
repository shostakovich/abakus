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
- No income group: income shows only in the month head's calculation
- A category row shows a pencil on hover and focus; it and the name open the category's dialog: name, target and
  deleting (the phone sheet shows the same parts after Verfügbar and auto-assign)
- Zugewiesen and Aktivität of a category stay blank at 0 (the assign field stays editable); Verfügbar 0 shows
  muted; group rows stay blank at 0 too, only the totals show 0,00. Group rows lie on a quiet band (base-200);
  amounts are never cut off
- Verfügbar is the anchor column: tinted from its title down and semibold; Aktivität is muted. Hovering Zugewiesen
  outlines only the cell under the pointer
- The current month at full contrast, without a label of its own; past months muted (red stays red); later months
  normal
- Verfügbar has no pills: red when overspent, amber with a small ring while the target is underfunded (only in
  months being budgeted: the current one and any other with money assigned; elsewhere plain), a green check for a
  funded target, a grey pause while snoozed, else plain. The marks stand behind the number in a slot every Verfügbar
  figure keeps, so the digits line up in every row. The ring fills by the share of the month's need
  that is assigned, rounded down (25,00 of 40,00 € is 62 %); hovered like an editable cell, Verfügbar opens the
  popover (cover, move, "Kategorie bearbeiten") for its month, which becomes the focus
- The category's dialog renames in place (Enter and leaving the field save, Escape puts the name back) and says
  the target in one sentence ("Jeden Monat auffüllen bis 650,00 €") with one status sentence: "Erfüllt.", "Im
  Plan." (by a date), "Noch 68,34 € diesen Monat." (with Zuweisen), "Überzogen um 180,20 €.", "Pausiert im
  Oktober."; only a target by a date has a bar (saved of its amount); spending a funded target leaves it funded
- A month head is one flat block above its columns: the month and a ghost ⋮ ("Verteilen"), then "Zu verteilen"
  as a tinted row (base-200; a green band above zero in an open month) with its chevron on the left and the amount
  on the right (green above zero, red below, plain at zero; a past month: "Nicht verteilt am Monatsende", muted and
  smaller), then the column titles with their totals; no popover. The corner keeps "Kategorie" and "+ Gruppe" and
  is as tall as the month head. The Mac has the same head, ⋮ instead of ⚡
- Verteilen (⋮): "Unterfinanzierte füllen (68,34 €)" with the month's underfunded total (only while something is
  underfunded and money is free), "In eine Kategorie …", "Zuweisung zurücksetzen"
- Zu verteilen shows and hides YNAB 4's calculation in every shown month at once, per device (collapsed by
  default, on the Mac too): between the month and Zu verteilen, on a base-200 band between hairlines, the amount
  right-aligned in its column, then the text: "5.947,86 € Nicht verteilt im Sep", "0,00 € Überzogen im Sep",
  "+255,00 € Einnahmen im Okt", "−5.915,41 € Zugewiesen im Okt", "Für spätere Monate" when not zero in an open
  month, then in red the later months it does not cover ("−300,00 € Nicht gedeckt im Nov")
- On phones the sticky month header has the same parts in the same order, compact: the month with ‹ › and ⋮, the
  calculation, Zu verteilen
- Months follow the budget's width: two from 760 px (a window of about 1100 px with the sidebar), three from
  1110 px (about 1450 px); the category column takes 22 % (224–320 px), the months the rest

## Register

- The header in two rows, web and Mac: the account's name, last reconcile and the pencil on the left, the balances
  ("Gebucht + Vorgemerkt = Arbeitssaldo") and "Abgleichen" (the page's only primary button) on the right; below,
  the toolbar with "Buchung", "Datei-Import" and what waits as chips ("2 bestätigen", "1 zuordnen"), then "Ansicht"
  and the search. The web also names the account's kind; the Mac has no file import and offers "Buchungen
  bearbeiten" in the context menu.
  Phones: the balances in one line, search and "Ansicht", "Buchung" as the "+"
- Newest first on both platforms, under a quiet month heading ("Oktober 2026", no total) that sticks while the list
  scrolls; rows then read "24.10.". Headings show only while the list is sorted by date (the web always is)
- Fixed columns, so an opened row keeps every column in place: Ausgang, Eingang and Saldo fit "−10.000,00", the memo
  takes the remaining width and is hidden per device from "Ansicht"; the column header sticks while the list scrolls.
  Eingang in green
- The category with its emoji only ("🛒 Lebensmittel"), also in the phone cards; its group shows in the tooltip and
  the picker. A missing category reads "⚠ Kategorie fehlt", a transfer "⇄ Depot", a split "Aufgeteilt (2)"
- One status column, last, as in Actual: ○ vorgemerkt, ✓ gebucht, 🔒 abgeglichen; a transaction waiting for approval
  shows its ✓ to approve there. Selection is a row highlight, not a column: ⌘ or Ctrl adds a row, Shift the rows up
  to it; on the web "Auswählen" in "Ansicht" makes every click add one (touch screens) and "Alle auswählen" takes
  the whole view. An opened row has Abbrechen and Speichern below it

## Icons

Setzkasten's rule: plush images (`AbakusWeb.Plush`, one WebP per motif in `priv/static/images/plush`) for the
sidebar, dock and area switch, the settings hub, empty-state figures, Kasse categories, Depot booking rows and
portfolio rows; Lucide for actions, status, warnings and chevrons. In the sidebar accounts show the
emoji of their name, one without the plush of `AbakusWeb.AccountMotif` (receipt for the shared-expenses account,
else by kind: landmark, piggy-bank, banknote, trending-up); a portfolio without emoji
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

# UI direction

Abakus should feel familiar to someone coming from YNAB 4, today's YNAB and Actual Budget: same structure, same
vocabulary, same interaction patterns. The visual language is felt-css in its clean look only (no felt look;
dense money tables don't suit it), not a new design. Take the best of each app.

References are public: Actual's demo (https://demo.actualbudget.org/budget), screenshots of YNAB 4 and today's
YNAB from the web and YNAB's help center. No screenshots of real budgets in this repo.

## From YNAB 4

- Months side by side: 1, 2 or 3, chosen automatically from the window width, recalculated on resize, no manual
  setting; one month on phones
- Month header explains RTA: not assigned last month − overspent last month + income − assigned = Zu verteilen
  (red "Zu viel verteilt" only in imported history)
- Column headers carry the month totals; fixed category column; months as separate blocks
- Month strip with year, selected range highlighted, arrows at both ends

## From today's YNAB

- Dark sidebar: budget name, Budget, Konten, account groups (Budget, Tracking) with balances, add account, bank
  connections; account names with emoji
- Zu verteilen colours: green with "Verteilen ▾" while money is unassigned, grey when everything is assigned,
  red if negative; line "In künftigen Monaten zugewiesen" (shown in the month card, see decisions below)
- Filter chips: Alle, Überzogen (count, red), Unterfinanziert, Überfinanziert, Geld verfügbar, Pausiert
- Columns ZUGEWIESEN | AKTIVITÄT | VERFÜGBAR; available as pills (check = funded, half circle = underfunded,
  red = overspent, grey = 0)
- Targets: bar and status under the category name ("Finanziert", "Im Plan", "Noch 13,99 € nötig bis zum 31.",
  "Überzogen. 116,98 € von 88,99 €"); inspector with ring, "Weise noch X zu" + "Zuweisen", target editor
- Inspector: month summary, targets this month, auto-assign (underfunded, as last month, spent last month,
  average, reset), assigned in future months; "cover overspending" popover picking the source category
- Register: balance equation (cleared + uncleared = working), banner "n neue Buchungen zu bestätigen", unapproved
  rows marked, categories prefilled from the payee, outflow/inflow columns, cleared "C" / lock
- Reconcile popover: latest bank balance vs. cleared balance, "Passt!" in one click, otherwise difference and
  adjustment transaction

## From Actual

- Month cards and per-month column groups in the multi-month table; group rows with totals; collapsible groups

## Decisions after review round 1

- Width rule: inspector before a third month. About 1280 px → 1 month + inspector, 1600 → 2 + inspector,
  1920 → 3 + inspector; below that months only. Still automatic, no selector
- One home per concept: Zu verteilen lives only in the month cards (on phones in a sticky month header); the
  inspector shows the selected category or the month summary, never its own RTA box
- Focus month: full month card with the YNAB 4 calculation, pills, target bars and status; other months get
  slim cards (big number, Verteilen, calculation collapsible) and quiet numbers (zeros dimmed, negatives red,
  a dot for underfunded). Light month card in clean light
- Two-line category rows like YNAB: name on line 1, bar and status on line 2; rows about 36 px
- Clean look only: the felt look is dropped (owner decision), no look toggle; the table body stays flat

## Method

Every euro gets assigned and overspending is dealt with: RTA > 0 and overspent categories are open tasks, RTA =
0 with nothing overspent is the resting state. Abakus never lets an assignment push RTA below zero (no
borrowing from next month's income).

## Review

Two art-director subagents rate every screen 1–10 with concrete feedback, per theme (clean light, clean dark), desktop (3, 2, 1 months) and phone (390 px):

- AD A, material/craft: felt-css fit (clean look), typography, spacing, numbers, details
- AD B, UI/product: hierarchy, familiarity for YNAB/Actual users, task flow, mobile, dark contrast

Both get the reference screenshots and the brief "steal the best from all three".

Round 1 is exploration, not polish: avoid a local maximum. The ADs say what is missing, what the references do
better, and where the screens should ideally go (direction, bigger structural changes, alternatives worth
trying), with a first score only as a baseline. The direction is agreed before polishing. From round 2 they rate
and say what is missing for 9.5. After every round the owner gets a score table with the history. Stop at 9.5.

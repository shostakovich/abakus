# UI direction

Abakus should feel familiar to someone coming from YNAB 4, today's YNAB and Actual Budget: same structure, same
vocabulary, same interaction patterns. The visual language is felt-css in its clean look only (no felt look;
dense money tables don't suit it), not a new design. Take the best of each app.

References are public: Actual's demo (https://demo.actualbudget.org/budget), screenshots of YNAB 4 and today's
YNAB from the web and YNAB's help center. No screenshots of real budgets in this repo.

## From YNAB 4

- One month on phones

## From today's YNAB

- Sidebar: bank connections
- "Verteilen ▾" on Zu verteilen while money is unassigned
- Targets: inspector with ring, "Weise noch X zu" + "Zuweisen", target editor
- Inspector: targets this month, overspent categories, auto-assign (underfunded, as last month, spent last month,
  average, reset); "cover overspending" popover picking the source category

## Decisions after review round 1

- On phones Zu verteilen lives in a sticky month header; the inspector shows the selected category or the month
  summary

## Method

Every euro gets assigned and overspending is dealt with: RTA > 0 and overspent categories are open tasks, RTA =
0 with nothing overspent is the resting state.

## Review

Two art-director subagents rate every screen 1–10 with concrete feedback, per theme (clean light, clean dark), desktop (3, 2, 1 months) and phone (390 px):

- AD A, material/craft: felt-css fit (clean look), typography, spacing, numbers, details
- AD B, UI/product: hierarchy, familiarity for YNAB/Actual users, task flow, mobile, dark contrast

Both get the reference screenshots and the brief "steal the best from all three".

Round 1 is exploration, not polish: avoid a local maximum. The ADs say what is missing, what the references do
better, and where the screens should ideally go (direction, bigger structural changes, alternatives worth
trying), with a first score only as a baseline. The direction is agreed before polishing. From round 2 they rate
and say what is missing for 9.5. After every round the owner gets a score table with the history. Stop at 9.5.

Status 2026-10-08: seven rounds, both ADs at 9.5 or higher on every screen in light and dark (desktop 1100–1920
with full and collapsed sidebar, phone 390 px).

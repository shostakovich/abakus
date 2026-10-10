## 0003. Categories are deleted only with a transfer

Accepted, 2026-10-10. Replaces "hidden, never deleted" from the spec.

- **Context:** After the switch YNAB no longer shapes the categories, so Abakus has to add, rename and remove
  them. Hiding (YNAB's way to retire a category) keeps old envelopes around for good and needs a second kind of
  category everywhere: in the budget, the pickers, filling and name lookups.
- **Decision:** There is no hiding. Deleting a category names a regular category that takes over everything:
  transactions and split lines (deleted ones, match proposals and the budget side of transfers to tracking accounts
  included), payees' last categories and the assignments, added per month. Targets and snoozes go with the
  category. Reconciled transactions change too, after the user confirms it. A group is deleted only when it is
  empty. YNAB's hidden flag stays on groups and categories for the import and its check; the budget ignores it.
- **Consequences:** History keeps its references and every past month's Ready to Assign and sum of available stay
  as they were, as long as neither category was overspent in a month where the other had money; merging
  envelopes covers such overspending, so Ready to Assign changes from that month on, as in YNAB. Deleted
  categories are gone, also from the API; there is no undo.

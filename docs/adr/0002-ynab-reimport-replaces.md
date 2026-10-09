## 0002. The YNAB re-import wipes and reloads the budget

Accepted, 2026-10-09

- **Context:** The YNAB import runs again and again until the switch, and YNAB stays the source of truth until
  then; Abakus holds nothing of its own yet, and the API clients only move to Abakus afterwards.
- **Decision:** Each run deletes the whole budget domain (everything but users and the internal Ready to Assign)
  and loads the YNAB export anew, in one database transaction; it refuses to run once any transaction, deleted
  ones included, has a source other than `ynab`. Matching by YNAB ids (an id column on accounts, groups,
  categories and payees, updates through the Ledger's rules) was rejected as much more work for data that does not
  need to survive.
- **Consequences:** Ids change on every run, so nothing may hold them before the switch; accounts or categories
  created in Abakus without transactions are lost on a re-import, and after the switch the import cannot be used
  to catch up.

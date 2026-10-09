# External ids live in their own table

External ids are kept in `transaction_origins` (transaction, account, source, external id; unique per account,
source and external id) instead of a column on the transaction. When an import is matched to an existing
transaction, the existing one survives with its id (API clients hold it) and gets the import's origin attached,
so a re-import still finds it and is not imported twice; `source` on the transaction stays where it was first
created.

Until the match is decided, the import is a row of its own with `matched_transaction_id`: a pending proposal that
counts nowhere (listings and balances skip it), one per existing transaction, with its account and amount fixed
while it is open. Accepting moves its origins to the existing transaction, which takes the import's date and cleared
state and keeps its category and memo where it has them, and removes the row; rejecting ("Trennen") clears the
pointer and approves the import as a transaction of its own. Origins follow their transaction when it moves to
another account; a move into an account that has the same external id from the same source is refused.

## Considered options

- An `external_id` column on the transaction: one id per transaction, so a matched transaction loses either its
  own id (breaking API clients) or the import's id (the next import creates a duplicate).
- Keeping the imported row as a hidden duplicate after the match: dedupes, but leaves two rows for one booking that
  every balance, report and API response has to skip for good, not only while the match is open.

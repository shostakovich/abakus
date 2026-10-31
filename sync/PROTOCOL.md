# Sync protocol

How Abakus and the Apple apps keep one budget (spec #102, ADRs 0024–0027). This document grows with the sync; it
starts with how rows get their ids, so that every writer makes the same ones.

## Ids

Every row of a synced table has a UUID as its id, and every column that points at such a row holds that UUID
(ADR 0025). Ids travel and are stored as text: lowercase, hyphenated, 36 characters
(`01890a5d-ac96-774b-bcce-b302099a8057`). A writer lowercases an id it did not make before storing or
comparing it.

The synced tables are `accounts`, `payees`, `payee_rename_conditions`, `transactions`, `subtransactions`,
`scheduled_transactions`, `scheduled_subtransactions`, `category_groups`, `categories`, `assignments`,
`target_versions` and `target_snoozes`. Users, the Kasse and the Depot keep integer ids and are not synced.

### New rows

A new row gets a UUIDv7 (RFC 9562): its first 48 bits are the Unix time in milliseconds, so ids sort roughly by
creation. Where rows are ordered by position, a tie orders by id.

### Rows with a natural key

A row that two writers could create independently for the same thing gets a name-based UUIDv5 (RFC 9562, SHA-1)
instead, so both make the same row and their changes meet in it. The namespace is

    1d70d95f-102c-4115-966f-5db73210e37c

and the name is the parts below joined by `/`, with ids as lowercase text and dates as ISO 8601 (`2026-11-01`;
a month is its first day):

| Row | Name |
| --- | --- |
| An assignment | `assignment/<category id>/<month>` |
| A target snooze | `target_snooze/<category id>/<month>` |
| A target version | `target_version/<category id>/<first month>` |
| An account's transfer payee | `transfer_payee/<account id>` |
| A transaction entered from a scheduled transaction | `entered_transaction/<scheduled transaction id>/<date>` |

With the category or account `01890a5d-ac96-774b-bcce-b302099a8057`:

| Name | Id |
| --- | --- |
| `assignment/01890a5d-ac96-774b-bcce-b302099a8057/2026-11-01` | `6acb0211-c88e-59b4-baca-87f0fe072024` |
| `target_snooze/01890a5d-ac96-774b-bcce-b302099a8057/2026-11-01` | `40ec28ed-8c55-5958-9143-194ff78e701e` |
| `target_version/01890a5d-ac96-774b-bcce-b302099a8057/2026-11-01` | `dbbd70b6-fe59-5ed4-b545-d4b106935aee` |
| `transfer_payee/01890a5d-ac96-774b-bcce-b302099a8057` | `e884f20e-330e-5cd4-adbd-a7bbed724916` |
| `entered_transaction/01890a5d-ac96-774b-bcce-b302099a8057/2026-12-01` | `28bca64b-3fac-52b1-8dde-6a7a1ce968b0` |

The parts and the counterparts of an entered transaction get new UUIDv7s like any new row.

## Scheduled transactions

A scheduled transaction is entered on its `next_date` as an unapproved transaction with the id above, which
records `scheduled_transaction_id` and `scheduled_date`. A writer that finds that id taken does not enter the
occurrence again. Then `next_date` moves on by the frequency, and one with frequency `once` is deleted. Writers
must step alike, or their entered ids part:

- `daily`, `weekly`, `every_other_week`, `every_4_weeks`: 1, 7, 14 or 28 days on.
- `monthly`, `every_other_month`, `every_3_months`, `every_4_months`, `twice_a_year`: 1, 2, 3, 4 or 6 months
  on, the same day of the month or the month's last day if it is shorter (January 31 → February 28 → March 28).
- `yearly`, `every_other_year`: 1 or 2 years on, February 29 becoming February 28.
- `twice_a_month`: on `first_day` and `second_day` (1 ≤ first < second ≤ 31), a day the month lacks being its
  last day: the next of the two after the date in its month, else `first_day` of the next month.

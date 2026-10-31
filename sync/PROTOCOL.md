# Sync protocol

How Abakus and the Apple apps keep one budget (spec #102, ADRs 0024–0027): how rows get their ids, so that every
writer makes the same ones, how changes travel as messages that every writer merges alike, how an app signs in and
the API it syncs through.

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
| A part of an entered transaction, by its position from 0 | `entered_subtransaction/<entered transaction id>/<position>` |
| The counterpart of a transfer's side (a transaction or a part) | `transfer_counterpart/<side id>` |

With the category or account `01890a5d-ac96-774b-bcce-b302099a8057`:

| Name | Id |
| --- | --- |
| `assignment/01890a5d-ac96-774b-bcce-b302099a8057/2026-11-01` | `6acb0211-c88e-59b4-baca-87f0fe072024` |
| `target_snooze/01890a5d-ac96-774b-bcce-b302099a8057/2026-11-01` | `40ec28ed-8c55-5958-9143-194ff78e701e` |
| `target_version/01890a5d-ac96-774b-bcce-b302099a8057/2026-11-01` | `dbbd70b6-fe59-5ed4-b545-d4b106935aee` |
| `transfer_payee/01890a5d-ac96-774b-bcce-b302099a8057` | `e884f20e-330e-5cd4-adbd-a7bbed724916` |
| `entered_transaction/01890a5d-ac96-774b-bcce-b302099a8057/2026-12-01` | `28bca64b-3fac-52b1-8dde-6a7a1ce968b0` |
| `entered_subtransaction/28bca64b-3fac-52b1-8dde-6a7a1ce968b0/0` | `14ba82c4-51c1-5ecd-ba82-b995012c3b39` |
| `transfer_counterpart/01890a5d-ac96-774b-bcce-b302099a8057` | `9c88c356-e185-5efa-b9f0-818a4644aebf` |

So two writers that enter the same occurrence of a split or a transfer make the same parts and counterpart, and two
that make the same side a transfer make one counterpart. A side that becomes a transfer again after its counterpart
was deleted brings that counterpart back: it writes the counterpart's fields anew and clears its `deleted_at`.

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
  last day: the next of the two after the date in its month, else the earlier of the two in the next month.

A writer that changes one of `frequency`, `first_day` and `second_day` writes all three, with one clock, and the
other frequencies have neither day. As messages merge field by field, a writer still takes the two days in either
order, and steps a `twice_a_month` schedule without two different days from 1 to 31 as `monthly`. Likewise a target
version whose `cadence` lacks what it needs (`monthly` an `amount`, `by_date` an `amount` and a `due_on`) is no
target.

## Messages

Every change of a synced row is one message per changed field:

| Field | |
| --- | --- |
| `table` | the table's name, e.g. `transactions` |
| `row_id` | the row's id |
| `column` | the column's name, e.g. `memo` |
| `value` | the new value as JSON (below) |
| `clock` | the writer's clock (below) |

The server stores them with the user and the device and numbers each user's messages in order of arrival; that
number is the cursor a device reads after. Values are JSON: amounts in cents and other numbers as integers, dates as
ISO 8601 (`2026-11-02`), moments as ISO 8601 UTC with microseconds (`2026-11-02T10:00:00.000000Z`), ids as UUID
text, enums and other texts as strings, booleans, and `null`.

A synced table syncs all its columns but `id`, `user_id`, `inserted_at`, `updated_at`, `lookup_key` (each writer
derives it from `name`, see [Lookup keys](#lookup-keys)), an account's `ofx_bank_id` and `ofx_acct_id`, and a transaction's `kasse_expense_id` and
`depot_transaction_id`. In their place a transaction's `led_by` names the area that leads it, `kasse`, `depot` or
`null` (see [Led transactions](#led-transactions)). A part (`subtransactions`, `scheduled_subtransactions`) belongs to
the user of its parent.
Never synced: computed figures, users and tokens, origins and external ids, bank connections, linked accounts, sync
runs, bank balances, the Kasse and the Depot.

A writer that creates a row sends a message for each column that is not `null`; one that changes a row, one for
each column that changed. All messages of one change carry one clock, so a transfer's two sides, or a split with
all its parts, win or lose together. A message always has a `value`; one without is refused, as `null` is a value of
its own. A writer that creates an account creates its transfer payee with it: the id above, the name
`Transfer : <account name>` and the account as `transfer_account_id`, renamed with the account. The server creates
the transfer payee of an account a device's messages left without one.

## Clock

A hybrid logical clock: wall time in milliseconds, a counter and the device id, compared in that order. It is
written as one text that sorts like the clock: UTC time with milliseconds, the counter as four lowercase hex
digits, the device id (lowercase letters, digits and hyphens):

    2026-11-02T10:00:00.000Z-0000-server

The server is the device `server`. For a change, a writer takes its newest clock: if the wall time is later, the
clock is the wall time with counter 0, else the same time with the counter one up. The counter goes up to
`ffff`; a clock past that is the next millisecond with counter 0. A writer's newest clock is the
newest it has written or received, so receiving a newer clock moves its own past it.

## Merging

Messages for tables or columns a writer does not know are ignored. Each field has the clock of its current value. A
message changes its field only when its clock is newer; an older one is still stored. A message with the same clock
for the same table, row and column as one stored already is ignored, so a push can be repeated. A row that does not
exist yet is created from its messages, its other columns taking their defaults; on the server it belongs to the
device's user, and a message for another user's row, or with an id of another user's row as its value, is dropped.

## Led transactions

A transaction is led when its own `led_by` or its transfer counterpart's is set: the Kasse or the Depot wrote it on
the server and leads it (ADR 0020). Its `account_id`, `date`, `amount`, `payee_id`, `transfer_transaction_id`,
`transfer_subtransaction_id` and `deleted_at`, and every field of its parts, follow the source; `category_id`,
`memo`, `cleared` and `approved` are the devices' like any other field. Only the server writes `led_by`, a
transaction's `matched_transaction_id` (an import that may be a duplicate) and an account's `shared_expenses` (the
account the Kasse writes into).

The server does not apply a device's message for a field the source leads or only the server writes, nor one that
would join another row to a led transaction (a transaction's `transfer_transaction_id`, a part's `transaction_id` or
`transfer_transaction_id`); it stores it like an older one and writes the field's current value again with a newer
clock, so the device converges back. A part a device adds to a led transaction the server creates and deletes again.
Apps offer none of these edits.

## Rules that converge

- **Deleting is a tombstone.** A deleted row stays, with `deleted_at` set. Accounts are closed, never deleted. A
  transaction stands for its parts; a part removed from a split is deleted on its own.
- **Successors.** Deleting a category and merging payees also set `successor_id`. Whatever still points at a deleted
  category or a merged payee counts for its successor, or that one's while it is deleted too; a chain that comes
  back to a category ends at the smallest id of its cycle. The computed figures follow: a deleted category's
  transactions and assignments count for its successor, and what a category shows as assigned in a month is its
  own assignment plus those of the deleted categories that count for it. After applying messages, the server points
  what they pointed at a merged payee at the end of its chain, and moves what only it keeps, the Kasse's category
  mapping and the Depot's category for purchases, off a category they deleted.
- **Names.** No index keeps payee or category names unique, as two writers may give one name offline. After
  applying messages, the server merges the regular payees, and the categories in one group, that the messages
  created, renamed or moved and that share a lookup key with others, into the oldest, the one with the smallest id.
  It brings back a deleted category without a successor, the category a cycle of successors ends at, and a
  deleted group that still holds categories. It writes these like any writer.
- **Positions.** Concurrent moves may leave equal positions; ties order by id, and the next move renumbers its
  rows.

## Lookup keys

Payees and categories are matched by a lookup key derived from their name, which every writer derives alike:

1. Bring the name to Unicode NFC.
2. Replace each emoji with a space: a keycap sequence (`0`–`9`, `#` or `*`, an optional U+FE0F, U+20E3), a
   character of the category So or with the property Extended_Pictographic, Emoji_Modifier or Regional_Indicator,
   and U+200D, U+FE0E, U+FE0F, U+20E3 and U+E0020–U+E007F.
3. Normalize: collapse every run of whitespace to one space, trim, lowercase (Unicode's full mapping) and write
   `ß` as `ss`.
4. If that leaves nothing, the name is emoji only: remove from the NFC name only U+FE0E, U+FE0F and the skin tones
   U+1F3FB–U+1F3FF and normalize; if that leaves nothing too, normalize the NFC name.

So `🛒 Lebensmittel` is `lebensmittel`, `Straße` is `strasse` and `👍🏽` is `👍`.

## Signing in

Abakus is the OAuth 2.1 authorization server of the apps (ADR 0026); its metadata (RFC 8414) is at
`/.well-known/oauth-authorization-server`. The Apple apps are one public client:

| | |
| --- | --- |
| Client id | `abakus-apple` |
| Redirect URI | `local.abakus:/oauth/callback` (the callback scheme is `local.abakus`) |
| Grant | authorization code with PKCE, `S256` only; refresh token |

1. The app opens `/oauth/authorize` in a browser sheet with `response_type=code`, `client_id`, `redirect_uri`,
   `code_challenge` (unpadded base64url of the SHA-256 of a verifier of 43 to 128 characters),
   `code_challenge_method=S256`, `state` and `device_name`, the name the device is listed under (up to 60
   characters, e.g. `MacBook`). The page needs a signed-in session, so the owner signs in with their passkey
   first, then confirms; only the budget owner can.
2. Abakus redirects to the redirect URI with `code`, `state` and `iss` (the issuer, RFC 9207), or with `error`
   (`access_denied` when cancelled or refused, `invalid_request`, `unsupported_response_type`). An unknown client or
   another redirect URI gets no redirect.
3. The app posts the code to `/oauth/token` as a form: `grant_type=authorization_code`, `client_id`, `code`,
   `code_verifier` and, optionally, `redirect_uri`. A code is single use and lives 60 seconds; a failed exchange
   uses it up and the sign-in starts over.
4. The answer is JSON: `access_token` (valid for `expires_in`, 3600 seconds), `token_type` `Bearer`,
   `refresh_token` (valid for 90 days) and `device_id`, the device id the app writes its clocks with.
5. Before the access token runs out the app posts `grant_type=refresh_token`, `client_id` and `refresh_token` and
   gets new tokens of both kinds; the earlier ones stop working. Each refresh token works once: using one again
   signs the device out, as someone else may hold it. A device whose refresh fails signs in again, as a new device.
6. The app's own sign-out posts `client_id` and `token` (its access or refresh token) to `/oauth/revoke` (RFC 7009),
   which signs the device out and answers 200 for any token, also one that does not hold; another `client_id` gets
   401 with `invalid_client`.

Errors of the token endpoints are JSON `{"error": …}`: `invalid_grant` (400) for a code, verifier or refresh token
that does not hold, `invalid_client` (401), `unsupported_grant_type` and `invalid_request` (400). The budget owner
can also sign a device out under Einstellungen → Geräte.

## API

Every request carries `Authorization: Bearer <access token>` and `Abakus-Protocol: 1`, the protocol version. Without
a valid token the answer is 401 with `{"error": "invalid_token"}` and a `WWW-Authenticate: Bearer` header: the app
refreshes its tokens, or signs in again once that fails too. A version the server no longer speaks gets 400 with
`{"error": "unsupported_protocol", "supported": [1], "message": …}`, asking to update the app. Apps ignore tables,
columns and answer fields they do not know.

### Sync

`POST /api/sync` with a JSON body of the device's cursor and its pending messages, as in [Messages](#messages):

```json
{"cursor": 41, "messages": [{"table": "transactions", "row_id": "…", "column": "memo", "value": "Wocheneinkauf",
  "clock": "2026-11-02T10:05:00.000Z-0000-<device id>"}]}
```

The server applies the messages in one database transaction, all or none; their clocks must carry the device's id.
It answers with the messages after the cursor that came from other writers, the server included, in order of
arrival, at most 1000 read at a time, and the new cursor:

```json
{"cursor": 57, "messages": [{"table": "…", "row_id": "…", "column": "…", "value": …, "clock": "…"}],
 "more": false}
```

With `more` true the app syncs again at once. Once the answer has come, the pushed messages are stored and the app
drops them from its outbox; a push repeated after a lost answer is harmless. A request without messages that finds
nothing new waits up to 25 seconds for another writer and answers as soon as one writes; the app sends the next
right after, so changes arrive within seconds while it is online. A waiting request of a device signed out
meanwhile answers 401 with `invalid_token` once it wakes.

A push with a clock more than five minutes ahead of the server's time is refused whole with 400 and
`{"error": "clock_ahead", "clock": …, "server_time": …, "message": …}`: the app asks to set the device's clock.
Any other message the server cannot take, such as one that leaves a row pointing at a row that does not exist,
refuses the push with 400 and `{"error": "invalid_request", "detail": …}`.

### Snapshot

`GET /api/snapshot` answers a newly signed-in device with every synced row of the user, tombstones included, and
the cursor to sync after. The internal group and its Ready to Assign category are always among them, the server
creating them first, so every device has the server's ids:

```json
{"cursor": 57, "tables": {"transactions": [{"id": "…", "fields": {"memo": "Rewe", …},
  "clocks": {"memo": "2026-11-02T10:00:00.000Z-0000-server", …}}], …}}
```

`fields` holds every synced column of the row, `clocks` the clock of each field's value; a field without one has
never been changed through a message, so any message for it is newer.

## Shared cases

`sync/cases/` holds cases every implementation runs: a case's `setup` messages, then each device's messages in
every order, must give the `rows` (the listed columns of each row, as JSON values) and the `budget` figures (per
month and category: `assigned`, `activity`, `available`). A case with `"server_only": true` checks a rule only the
server applies, such as merging names, and the apps leave it out. The Elixir tests run them
(`test/abakus/sync/shared_cases_test.exs`), the Swift tests too (`apple/Tests/AbakusCoreTests/SharedCasesTests.swift`).

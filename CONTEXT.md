# Abakus

Envelope budgeting for one household, modelled on YNAB: every euro in the budget accounts is given a job in a
category. Terms are YNAB's in English; the German UI label follows in quotes.

## Language

### Budget

**Budget**:
The one plan of the household: categories with assignments per month, fed by the budget accounts. UI "Budget".
_Avoid_: Plan (YNAB API's name), envelope system

**Category group**:
A named, ordered set of categories in the budget, e.g. "🏠 Wohnen". UI "Kategoriegruppe".
_Avoid_: Master category

**Category**:
An envelope money is assigned to and spent from, e.g. "🛒 Lebensmittel"; hidden when no longer used, never deleted.
UI "Kategorie".
_Avoid_: Envelope, budget item

**Internal category**:
A category the app needs for itself and does not list with the others; Ready to Assign is the only one.
_Avoid_: System category

**Ready to Assign**:
Money that has come in but is not assigned to a category yet; income is booked to this internal category.
Cumulative per month; a month shows it less what later months have assigned. UI "Zu verteilen".
_Avoid_: To be budgeted, RTA in UI text, unassigned

**Assignment**:
The amount put into a category in a month; may be negative. UI "Zugewiesen".
_Avoid_: Budgeted, allocation

**Activity**:
The sum of a category's transactions in a month. UI "Aktivität".
_Avoid_: Spending, outflow

**Available**:
What a category holds at the end of a month: last month's available if positive, plus assignment and activity. UI
"Verfügbar".
_Avoid_: Balance (that is an account's), remaining

**Uncategorised**:
The budget row of transactions in budget accounts without a category; it carries and overspends like a category
but takes no assignments. UI "Nicht kategorisiert".
_Avoid_: Unassigned, no category

**Overspending**:
A negative available; the category starts the next month at zero and Ready to Assign pays the difference. UI
"Überzogen".
_Avoid_: Deficit, borrowing

**Uncovered month**:
A later month whose Ready to Assign is below zero, seen from an earlier month, which warns about it; assignments
are never refused for it. UI "nicht gedeckt".
_Avoid_: Shortfall month, borrowed month

### Targets

**Target**:
What a category should get: a monthly amount, or a yearly amount due on a date. UI "Ziel".
_Avoid_: Goal (YNAB API's name), savings goal

**Target version**:
A target as it applies from one month until the next version; changing or removing a target starts a new version, so
past months keep theirs.
_Avoid_: Target history

**Set aside**:
A target counting what is assigned in the month ("set aside another X"). UI "Weitere zurücklegen".
_Avoid_: Needs whole amount

**Refill**:
A target counting what is carried into the month plus what is assigned, spending aside ("refill up to X"). UI
"Auffüllen bis".
_Avoid_: Top up

**Snooze**:
A target counts as done in one month for one category: it still says what is missing, but the month's
underfunded total and filling leave it out, as in YNAB. UI "Pausiert".
_Avoid_: Skip, pause

### Accounts

**Account**:
A place money is kept, such as a current account, savings or cash; closed when no longer used, never deleted. UI
"Konto".
_Avoid_: Bank account (some are cash or depots), wallet; not a User

**Budget account**:
An account whose money belongs to the budget: checking, savings or cash. UI "Budget".
_Avoid_: On-budget account

**Tracking account**:
An account whose value is only tracked, outside the budget, e.g. a securities depot. UI "Tracking".
_Avoid_: Off-budget account, investment account

**Fed account**:
An account another app keeps up to date (`portfolio`: its value comes from a portfolio app; `shared_expenses`: its
transactions come from a shared-expenses app), so the UI offers no manual entry or file import for it; the Ledger
still accepts both.
_Avoid_: Synced account, linked account (that is bank sync)

**Reconcile**:
Confirming that an account's cleared balance equals the bank's balance, which locks its cleared transactions (they
become reconciled, "Abgeschlossen"). A reconciled transaction changes, directly or through its counterpart, only
after the user confirms; leaving the reconciled state is a change too. UI "Abgleichen".
_Avoid_: Balance check, sync

### Transactions

**Transaction**:
One booking in an account with a date and a signed amount (negative is an outflow). UI "Buchung".
_Avoid_: Entry, booking (in code), posting

**Payee**:
Who a transaction is with; remembers the category last used with it (match proposals do not count). UI "Empfänger".
_Avoid_: Merchant, counterparty, vendor

**Register**:
An account's transactions that count for listings and balances: not deleted and no match proposal.
_Avoid_: Booked transactions, journal

**Transfer**:
Money moving between two accounts: a pair of transactions, one in each account, each with the other's transfer
payee. The pair changes and goes as one: what is done to one side is done to its counterpart. UI "Umbuchung".
_Avoid_: Internal transfer, booking between accounts

**Counterpart**:
The other side of a transfer, in the account of the transfer payee: the amount negated, same date and memo.
Cleared state, approval and flag are each side's own. The counterpart of a subtransaction belongs to its split.
_Avoid_: Mirror, twin

**Transfer payee**:
The payee that stands for an account in transfers ("Transfer : Girokonto"); every account has one.
_Avoid_: Account payee

**Split**:
A transaction divided into subtransactions with their own category, payee and memo that add up to it; it is no
transfer as a whole. UI "Aufteilung", in the register "Aufgeteilt".
_Avoid_: Multi-category transaction

**Subtransaction**:
One part of a split, in the split's order; it may be a transfer of its own. UI "Teil".
_Avoid_: Line, split line, child transaction

**Cleared state**:
Whether the bank has a transaction yet: uncleared, cleared, or reconciled (locked by a reconcile). UI "Nicht
abgeglichen", "Abgeglichen", "Abgeschlossen".
_Avoid_: Status, booked; "bestätigt" (that is approval)

**Approval**:
A person has looked at an imported or API-created transaction and accepted it; manual entries are approved. UI
"Bestätigt", the action "Bestätigen".
_Avoid_: Confirmed, reviewed; "abgeglichen" (that is the cleared state)

**Flag**:
A colour marker on a transaction (red, orange, yellow, green, blue, purple). UI "Markierung".
_Avoid_: Tag, label

### Import

**Source**:
Where a transaction came from: manual, YNAB, file, bank or API.
_Avoid_: Channel, provider

**Origin**:
The record that a transaction was imported under an external id from a source into an account; a transaction can
have several.
_Avoid_: Import record

**External id**:
The id a source gives a transaction (FITID, the bank's or YNAB's id); unique per account and source.
_Avoid_: Import id, FITID (only files have those)

**Bank balance**:
What the bank reports an account holds on a date, from a file's ledger balance or from bank sync; reconciling
offers the latest. UI "Banksaldo".
_Avoid_: Ledger balance (OFX's name, `LEDGERBAL`), statement balance

**Match**:
An imported transaction that looks like an existing one, proposed for merging; never merged silently. Until it is
decided, the proposal counts nowhere and both keep their account and amount. Accepting merges it into the existing
transaction, which keeps its id and gets the import's origin; rejecting separates them and approves the import as a
transaction of its own. Only imports from a file or the bank propose; one proposal per existing transaction in the
register, in its account with its amount; a reconciled transaction takes none.
UI "passt zu", "Zuordnungsvorschlag"; accept "Zuordnen", reject "Trennen".
_Avoid_: Duplicate, merge

### Names

**Lookup key**:
What a name is looked up by: the name without emoji, ignoring case, spacing, "ß" against "ss" and how umlauts are
encoded, so "lebensmittel" finds "🛒 Lebensmittel" and "STRASSE" finds "Straße". A name of emoji only keeps them,
without variation selectors and skin tones. Ready to Assign's key is reserved for it.
_Avoid_: Slug, normalized name

### People

**User**:
A person who signs in; all users see and change the same budget.
_Avoid_: Account (that is where money is kept), member

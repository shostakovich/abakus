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
An envelope money is assigned to and spent from, e.g. "🛒 Lebensmittel"; deleted only into another category, which
takes over its transactions and money. UI "Kategorie".
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
What a category should get: a monthly amount, or an amount by a date, which repeats yearly or asks nothing after
its month. UI "Ziel".
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
An account whose value is only tracked, outside the budget, e.g. the cash at a broker. UI "Tracking".
_Avoid_: Off-budget account, investment account

**Shared-expenses account**:
The budget account the Kasse's budget link books into (`Account.shared_expenses`): its transactions are what Kasse
expenses and reimbursements change in the budget owner's Kasse balance, so the UI offers no manual entry, file
import or reconciling for it, as its balance is the Kasse's; the Ledger still accepts entries, and transfers from
other registers. No other account is kept by another area: a portfolio's value is no account's (ADR 0020).
_Avoid_: Fed account, synced account, linked account (that is bank sync)

**Reconcile**:
Confirming that an account's cleared balance equals the bank's balance, which locks its cleared transactions (they
become reconciled, "Abgeglichen"); one waiting for approval or a match decision stays cleared until then. A
reconciled transaction changes, directly or through its counterpart, only after the user confirms; leaving the
reconciled state is a change too. A bank balance counts the transactions up to its date, a balance entered by hand
up to today. UI "Abgleichen"; the register's subtitle "Abgeglichen am …" names the last one.
_Avoid_: Balance check, sync; "Abschließen", "abgeschlossen"

**Adjustment**:
The transaction reconciling books for a difference to the bank that cannot be found: payee "Ausgleichsbuchung",
approved and reconciled, in a budget account to Ready to Assign. UI "Ausgleichsbuchung".
_Avoid_: Correction, balancing entry

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
Cleared state and approval are each side's own. The counterpart of a subtransaction belongs to its split.
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
Whether the bank has a transaction yet: uncleared, cleared, or reconciled (locked by a reconcile), in a bank's
words: UI "Vorgemerkt", "Gebucht", "Abgeglichen" (with the lock); the balances read "Gebucht + Vorgemerkt =
Arbeitssaldo".
_Avoid_: Status, booked (in code); "Nicht abgeglichen" for uncleared, "Abgeglichen" for cleared (that is
reconciled), "Abgeschlossen"; "bestätigt" (that is approval)

**Approval**:
A person has looked at an imported or Kasse-created transaction and accepted it; manual entries are approved. UI
"Bestätigt", the action "Bestätigen".
_Avoid_: Confirmed, reviewed; "gebucht", "abgeglichen" (those are cleared states)

### Import

**Source**:
Where a transaction came from: manual, YNAB, file, bank, API, the Kasse or the Depot.
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

**Bank connection**:
The budget owner's access to one bank through Enable Banking (ADR 0021): its consent and the bank's accounts, each
feeding an account that takes entries from its start date on, or unlinked. UI "Bankverbindung".
_Avoid_: Requisition, bank link (links are the Kasse's and the Depot's), sync account

**Fetch**:
Bank sync asking the bank for a bank connection's transactions and balances: on schedule at 06:00 and 18:00, or on
"Jetzt abrufen" with the owner present; each one is kept as a sync run with its counts or error. UI "Abruf".
_Avoid_: Refresh, poll, sync (alone)

**Consent**:
What the budget owner grants at the bank for a bank connection: reading its accounts until a moment, as long as the
bank allows (90 to 180 days). A banner in Finanzen shows from 14 days before it ends until it is renewed; renewing
it ("Freigabe erneuern") consents anew and keeps the linked accounts. An ended one is not fetched. UI "Freigabe".
_Avoid_: Authorization, mandate, "Zustimmung"

**Match**:
An imported transaction that looks like an existing one, proposed for merging; never merged silently. Until it is
decided, the proposal counts nowhere and both keep their account and amount, unless the transaction's source (the
Depot or the Kasse) or a change to the other side of a transfer changes them: then the proposal is an ordinary import
again. Accepting merges it into the existing transaction, which keeps its id and gets the import's origin; rejecting
separates them and approves the import as a transaction of its own. Only imports from a file or the bank propose; one
proposal per existing transaction in the register, in its account with its amount; a reconciled transaction takes
none.
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
A person who signs in; sees the areas they may use.
_Avoid_: Account (that is where money is kept), member

**Budget owner**:
The one user who owns the budget, the first one invited; only they see the budget's pages in Finanzen.
_Avoid_: Admin, budget user

**Area**:
A part of the app with its own sidebar and dock: Finanzen and Kasse (ADR 0020). A user with both switches between
them at the top of the sidebar; `/` opens the area used last. Code areas such as `Abakus.Depot` are not areas of the
UI. UI "Bereich".
_Avoid_: Module, app, section (that is the sidebar's)

**Finanzen**:
The area of the budget and the portfolios: the budget's pages for the budget owner, Vermögen, Depots and Import &
Sync for everyone with the budget or a portfolio. Code: `:finanzen`. UI "Finanzen".
_Avoid_: Budget area, Depot area, finances

**Import & Sync**:
Finanzen's page for what comes in from outside, in tabs: Bankdateien (the budget owner's file import),
Bankverbindungen (their bank connections) and Belege (the inbox, for users with a portfolio). UI "Import & Sync".
_Avoid_: Settings (it is a task, not a setting)

**Settings hub**:
The sidebar's settings mode: a way back to the area used last, then the sections grouped by area, Allgemein for
everyone, Kasse for its participants; Depot for everyone, so anyone may start a Depot, with Belegeingang once they
have a portfolio. Pages live under `/settings/…`. Code: `AbakusWeb.SettingsNav`. UI "Einstellungen".
_Avoid_: Settings page, Mehr (that is the dock's button)

## Kasse

The shared expenses of one household: who paid what for whom, the balances that follow and how to settle them.
Code lives in `Abakus.Kasse` and `AbakusWeb.Kasse`, tables start with `kasse_`. Terms that the budget uses too
(category, activity, balance, split) mean the Kasse's here and are qualified in code (`Abakus.Kasse.Categories`).

**Kasse**:
The area of the shared expenses; only participants see it. UI "Kasse".
_Avoid_: Splitwise, shared budget

**Group**:
Everybody who shares expenses; there is one, with a name. UI "Gruppe".
_Avoid_: Household (that is the budget's), team

**Participant**:
A person of the group, who is a user; a user is at most one participant. Archived, never deleted, and without the
Kasse while archived. UI "Person", the list "Teilnehmer".
_Avoid_: Member, user (that is who signs in)

**Expense**:
What one participant paid for some of the group, split into shares; deleted ones stay in the activity log. UI
"Ausgabe".
_Avoid_: Transaction (that is the budget's), bill

**Reimbursement**:
A payment from one participant to another that settles a balance: an expense with a single share, the recipient's.
With the budget link, one that involves the budget owner is a transfer between the shared-expenses account and the
budget account they choose for it, entered in the Kasse or as a transfer in the register. UI "Rückzahlung".
_Avoid_: Transfer (that is the budget's), settlement

**Share**:
What a participant bears of an expense, in cents; the shares add up to the expense exactly. UI "Anteil".
_Avoid_: Portion, part

**Split mode**:
How an expense is divided: equally, by shares, by percent or by amounts. UI "Aufteilung".
_Avoid_: Split (that is the budget's divided transaction)

**Kasse balance**:
What a participant paid minus their shares, reimbursements included; positive means the others owe them. UI "Saldo".
_Avoid_: Available, debt

**Settlement**:
The reimbursements that bring every Kasse balance to zero, the largest debtor paying the largest creditor first.
UI "Vorgeschlagene Rückzahlungen".
_Avoid_: Netting

**Kasse category**:
A freely named, ordered kind of expense, e.g. "Lebensmittel"; archived, never deleted. UI "Kategorie".
_Avoid_: Unqualified Category in code (that is the budget's)

**Recurring expense**:
A rule that creates the same expense weekly, monthly or yearly, catching up on missed dates. UI "Wiederkehrende
Ausgabe".
_Avoid_: Scheduled transaction, template (that is the rule's copy of the expense)

**Activity entry**:
Who created, changed or deleted what in the Kasse, with the changes as old and new values. UI "Aktivität".
_Avoid_: Unqualified Activity in code (that is a budget category's sum), audit log

**Exchange rate**:
Units of a foreign currency per euro, the way the ECB quotes it; for an expense the ECB reference rate of its date,
or one entered by hand.
UI "Wechselkurs", "EZB-Kurs".
_Avoid_: FX rate in UI text

**Budget link**:
The budget owner's participant linked to the budget: what each expense changes in their Kasse balance, paid minus
share, is a linked transaction in the shared-expenses account, so its balance is their Kasse balance; each
Kasse category maps to a budget category for it. Their bank purchase of an expense they paid stays a purchase in its
category, which so bears only their share. A reimbursement with them is a transfer between that account and the
budget account they choose in the reimbursement form; until they choose one, it is a transaction there that still
needs an account. A transfer they book in the register between that account and a budget account becomes a
reimbursement with the group's other active participant, or the one they pick when there are several; it completes
an open reimbursement without account of the same amount, dated within the match window, instead. Switching it on
makes the chosen account the shared-expenses account and books every expense and reimbursement that changes
their balance. A link with a start date books an expense dated before it only when entered later or moved past it,
and a transfer dated before it creates nothing in the Kasse.
UI "Mit Budget verknüpfen", the settings page "Budget-Verknüpfung".
_Avoid_: Sync, budget export

**Linked transaction**:
A transaction another area writes into the budget and leads, referring to its source, an expense or a Depot
transaction (ADR 0020): amount, date, account, payee and transfer counterpart follow the source, and the Ledger
refuses changes to them, and deleting it, to anyone else; category, memo, cleared state and approval are the
register's, and a bank line matched to it keeps its date. A transfer's counterpart is led with it. In the Kasse, what
an expense changes in a linked participant's balance, written with the expense: paid minus share (none when that is
0), its date, its title as payee or for a reimbursement the transfer to its account, the mapped category (none for
a reimbursement), a memo describing the expense, unapproved; a transfer booked in the register keeps its own memo,
cleared state and approval when it becomes a reimbursement's. A change of the expense's Kasse category writes the
mapped category again, and the memo follows the expense while the register leaves it. In the Depot, see Cash side.
_Avoid_: Synced transaction, mirror

## Depot

Each user's portfolios: what they hold, what it is worth, what it paid and how it performed. Code lives in
`Abakus.Depot` and `AbakusWeb.Depot`, tables start with `depot_`. Terms that the budget uses too (transaction,
assignment, category) mean the Depot's here and are qualified in code (`Abakus.Depot.Portfolios.Transaction`,
`Abakus.Depot.Taxonomies.Assignment`); its accounts are the budget's, the accounts in Finanzen. Portfolios,
transactions and taxonomies belong to one user, who alone sees them; securities, prices, exchange rates and
compositions are shared by all.

**Depot**:
The code area of the portfolios (`Abakus.Depot`, `/depot`), shown in Finanzen as Vermögen and Depots; a user without
the budget gets Finanzen once they have a portfolio, created under Einstellungen › Depots. No UI area of its own.
_Avoid_: Portfolio app, investments, Depot area

**Security**:
A tradable instrument (ETF, fund, share) identified by its ISIN, with its own price history from Yahoo or manual;
on one day a manual price wins over Yahoo's. No screen enters prices: prices are shared, so one user's price would
move everyone's Vermögen. UI "Wertpapier".
_Avoid_: Asset, instrument, position

**Portfolio**:
A securities account at a bank; it holds shares of securities. UI "Depot".
_Avoid_: Securities account; Depot in code (that is the code area)

**Depot number**:
The number the bank gives a portfolio, as its documents print it; only its digits count when comparing. UI
"Depotnummer".

**Verrechnungskonto**:
The account in Finanzen a portfolio's purchases, sales and dividends settle against by default (ADR 0020); each
portfolio has exactly one, and a Depot transaction may move money on any other account of its user. Its kind decides
whose money it is, for active and retired portfolios alike. A budget account, such as the checking account a
portfolio pays from, stays the budget's, and several portfolios may share it. A tracking account is the portfolio's
cash at the broker and the Verrechnungskonto of no other portfolio: its balance counts toward the portfolio's value
in the sidebar and shows in its Bestand; its money moves in the Depot, so the budget's registers leave it out, Alle
Konten included, no account picker there and no file import offers it, and its own register leads to the portfolio,
while a transfer from another account still shows in that account's register. A new portfolio comes with a new
tracking account as its Verrechnungskonto; the Depot settings change it and rename, close and reopen a tracking one.
Code: `Portfolio.reference_account`, the cash by `Abakus.Depot.Portfolios.cash_account_portfolios/1`. UI
"Verrechnungskonto", in the Bestand the cash "Cash", "davon Cash".
_Avoid_: Depot account, clearing account, reference account, Referenzkonto

**Holding**:
The shares of one security in one portfolio on a date, with their value and purchase value. UI "Position"; the
holdings screen is "Bestand".
_Avoid_: Position in code

**Net worth**:
The money in a user's accounts plus the value of all their holdings on a date, in euros, each counted once. For the
budget owner the Ledger's net worth, all budget and tracking accounts but those closed with money left in them that
the Depot does not use, plus the holdings, from the earlier of the budget's and the Depot's first day
(`Abakus.Depot.Wealth`); for anyone else the balances of their Verrechnungskonten plus the holdings. UI "Vermögen".

**Invested capital**:
What came in from outside up to a date: deposits − removals + inbound deliveries − outbound deliveries; a purchase
from a Verrechnungskonto moves money inside and changes nothing. UI "Investiert".

**Purchase value**:
What the shares of a holding cost by FIFO, including the fees and taxes of their purchases; the gain is the value
minus the purchase value. UI "Einstand".

**Distribution**:
What a security paid per share on a payment date, from the user's dividend transactions, gross, in euros as booked.
UI "Ausschüttung".

**Benchmark**:
The security a user compares their portfolios with, kept in their Depot settings; each user picks their own, or
none. UI "Benchmark".

**Shadow portfolio**:
What the user's money would be worth in the benchmark: it starts with the net worth of the chart's first day, and
every deposit, removal or delivery buys or sells benchmark shares that day. UI "Schattendepot".

**Dividend**:
What a user receives or will receive for their shares of a security on a pay date: booked, announced by DivvyDiary,
or a forecast from the last 12 months' distributions (with less than a year of them, the latest repeated in its
usual rhythm); its net is the gross minus taxes and fees. UI "Dividende", "angekündigt", "Prognose", "Netto".
_Avoid_: Payment

**Depot transaction**:
One business event, such as a purchase, a dividend or a transfer, with a portfolio side, an account side or both
(ADR 0013), booked in euros whatever the security's currency; its units are fee and tax. Code:
`Abakus.Depot.Portfolios.Transaction`. UI "Buchung".
_Avoid_: Transaction unqualified in code (that is the budget's), entry

**Cash side**:
What a Depot transaction moves on its Verrechnungskonten, written there as a linked transaction it leads (ADR
0020), a cash transfer between two of them as a transfer, led from its budget side if it
has one, in the Depot change's database transaction: into a tracking account its whole history, cleared and
approved, without category; into a budget account only through the Depot link. A purchase or sale is with the
portfolio, another transaction with its security, and a cash transfer's side without the other with that account;
the memo names the kind and the security. Code: `Abakus.Depot.CashSide`.

**Depot link**:
The budget owner's Depot linked to the budget (ADR 0020), switched on under Einstellungen › Depots with a start date
and the category for purchases. From the start date on, the cash side of their purchases, sales, dividends and cash
transfers on a budget account is written into that account, unapproved: an
outflow in that category, an inflow to Ready to Assign, none for a transfer between budget accounts. Its other
transactions there, and all before the start date, are the bank import's. Code: `Abakus.Depot.BudgetLink`. UI "Mit Budget verknüpfen".
_Avoid_: Budget link (that is the Kasse's), sync

**Receipt**:
A bank's PDF for a Depot transaction, such as a purchase confirmation or a dividend statement, uploaded or taken from
the user's Paperless; it stays attached to the transaction booked from it. Its file is stored once, by its SHA-256,
in `receipts/` next to the database. Code: `Abakus.Depot.Portfolios.Receipt`. UI "Beleg".
_Avoid_: Document, statement

**Inbox**:
A user's receipts waiting for them to confirm, correct or discard what a language model recognised in them (ADR
0015); nothing is booked without confirmation. Code: `Abakus.Depot.Receipts`. UI "Eingang", Import & Sync's tab "Belege".

**Receipt intake**:
Where a user's receipts come from besides uploads: their own Paperless-ngx, polled every 15 minutes for documents
with their tag (ADR 0016), kept in their Depot settings. UI "Belegeingang".

**Taxonomy**:
A user's named tree of classifications with target weights, such as regions or asset classes; securities and
Verrechnungskonten are assigned to its classifications with weights. UI "Klassifizierung", a classification
"Kategorie", an assignment "Zuordnung".
_Avoid_: Category or Assignment unqualified in code (those are the budget's)

**Composition**:
A fund's shares per country and per sector, as DivvyDiary reports them; not set by the user. UI "Zusammensetzung".
_Avoid_: Look-through

**Allocation**:
The shares of the shown securities' value per region or sector, or of the assigned value per top-level
classification, against its target weight. UI "Aufteilung".

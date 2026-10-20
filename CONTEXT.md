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
An account whose value is only tracked, outside the budget, e.g. a securities depot. UI "Tracking".
_Avoid_: Off-budget account, investment account

**Fed account**:
An account another area keeps up to date (`portfolio`: the tracking account that one of the budget owner's
portfolios is, opened with the portfolio and closed once it is gone, its value kept by the value change;
`shared_expenses`: its transactions are the budget owner's shares of Kasse expenses), so the UI offers no manual
entry, file import or reconciling for it, as its balance is the other area's; the Ledger still accepts entries.
_Avoid_: Synced account, linked account (that is bank sync)

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
The budget owner's access to one bank through Enable Banking (ADR 0020): its consent and the bank's accounts, each
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
A person who signs in; sees the areas they may use.
_Avoid_: Account (that is where money is kept), member

**Budget owner**:
The one user who owns the budget, the first one invited; only they see the budget's pages in Finanzen.
_Avoid_: Admin, budget user

**Area**:
A part of the app with its own sidebar and dock: Finanzen and Kasse (ADR 0017). A user with both switches between
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
UI "Rückzahlung".
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
The budget owner's participant linked to the budget: their share of every expense is a linked transaction in the
account fed by `shared_expenses`, so its balance is their Kasse balance; each Kasse category maps to a budget
category for it. Switching it on makes the chosen account the one fed by `shared_expenses` and books every
expense. A link with a start date books an expense dated before it only when entered later or moved past it.
UI "Mit Budget verknüpfen", the settings page "Budget-Verknüpfung".
_Avoid_: Sync, budget export

**Linked transaction**:
A transaction another area writes into the budget and leads: amount, date and payee follow it, the register keeps
the category, memo and approval it set, and it is deleted only with what it is linked to. In the Kasse, a
linked participant's share of an expense, written with the expense: minus the share, its date, its title as payee,
the mapped category, a memo describing the expense, unapproved; a change of the expense's Kasse category writes the
mapped category again. In the Depot, see Depot link.
_Avoid_: Synced transaction, mirror

## Depot

Each user's portfolios: what they hold, what it is worth, what it paid and how it performed. Code lives in
`Abakus.Depot` and `AbakusWeb.Depot`, tables start with `depot_`. Terms that the budget uses too (account,
transaction, assignment, category) mean the Depot's here and are qualified in code (`Abakus.Depot.Portfolios.Account`,
`Abakus.Depot.Taxonomies.Assignment`). Portfolios, Verrechnungskonten, transactions and taxonomies belong to
one user, who alone sees them; securities, prices, exchange rates and compositions are shared by all.

**Depot**:
The code area of the portfolios (`Abakus.Depot`, `/depot`), shown in Finanzen as Vermögen and Depots; a user without
the budget gets Finanzen once they have a portfolio, created under Einstellungen › Depots. No UI area of its own.
_Avoid_: Portfolio app, investments, Depot area

**Security**:
A tradable instrument (ETF, fund, share) identified by its ISIN, with its own price history from Yahoo or manual;
on one day a manual price wins over Yahoo's. No screen enters prices: prices are shared and feed the value change,
so one user's price would move the budget. UI "Wertpapier".
_Avoid_: Asset, instrument, position

**Portfolio**:
A securities account at a bank; it holds shares of securities. UI "Depot".
_Avoid_: Securities account; Depot in code (that is the code area)

**Depot number**:
The number the bank gives a portfolio, as its documents print it; only its digits count when comparing. UI
"Depotnummer".

**Verrechnungskonto**:
A cash account of the Depot, in euros; it exists on its own, not as part of a portfolio. The one a portfolio's
purchases, sales and dividends settle against by default is its reference account; several portfolios may share one.
Code: `Abakus.Depot.Portfolios.Account`. UI "Verrechnungskonto", the reference account "Referenzkonto" where it is one.
_Avoid_: Account unqualified in code (that is the budget's), cash account

**Role** (of a Verrechnungskonto):
What a Verrechnungskonto is in Finanzen, set under Einstellungen › Depots (ADR 0017): a budget account, the cash of a
portfolio, or none; without a role set it shows as a warning on Vermögen. A portfolio's new Verrechnungskonto starts
as its cash. Code: `Abakus.Depot.AccountRoles`, `Account.role/1`. UI "Rolle", "Rolle fehlt".

**Budget account role**:
The role of a Verrechnungskonto that is the same bank account as a budget account: the budget owner's only,
at most one per budget account; it counts toward nothing else, and once the Depot link is on its flows with the
user's portfolios are linked transactions in that budget account. UI "ist Budgetkonto „X“".

**Portfolio cash**:
The role of a Verrechnungskonto that is cash held at the broker of one of the user's portfolios: its
balance counts toward that portfolio's value, in the sidebar and its value change, and shows in its Bestand. UI
"Cash von Depot „Y“", in the Bestand "davon Cash".
_Avoid_: Cash account (that is any Verrechnungskonto)

**Holding**:
The shares of one security in one portfolio on a date, with their value and purchase value. UI "Position"; the
holdings screen is "Bestand".
_Avoid_: Position in code

**Net worth**:
The value of all of a user's holdings plus the balances of their Verrechnungskonten on a date, in euros. UI
"Vermögen".

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

**Value change**:
The daily transaction, after the price job, in a portfolio's account (fed by `portfolio`): the portfolio's value,
its cash included, minus the account's balance, approved and cleared; none without a difference, so a new account starts at the
portfolio's value. One per day: another run that day amends it, and deletes it once nothing differs. Besides it, only
the transfers of the Depot link write to the account, so the value change keeps the market movement and the income
inside the portfolio; it cannot be reconciled. Code: `Abakus.Depot.BudgetFeed`. UI "Wertänderung" (its payee).
_Avoid_: Revaluation, market value adjustment

**Depot link**:
The budget owner's Depot linked to the budget (ADR 0018), switched on under Einstellungen › Depots with a start date
and the category for purchases. Every Depot transaction since the start date between one of their portfolios
and a Verrechnungskonto with the budget account role is a linked transaction in that budget account, written in the
Depot change's database transaction: a purchase or a cash transfer into a portfolio's cash is
an outflow in that category, a sale or a cash transfer back an inflow to Ready to Assign, each a transfer to the
portfolio's account, unapproved; a dividend is an inflow to Ready to Assign with the security as payee. Flows inside
a portfolio's own cash stay out. Code: `Abakus.Depot.BudgetLink`. UI "Mit Budget verknüpfen".
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

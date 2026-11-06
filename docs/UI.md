# UI direction

Abakus should feel familiar to someone coming from YNAB 4, today's YNAB and Actual Budget: same structure, same
vocabulary, same interaction patterns. The visual language is Setzkasten's (flat pages, one
accent, hairlines, tabular numbers), not a new design. Take the best of each app.

References are public: Actual's demo (https://demo.actualbudget.org/budget), screenshots of YNAB 4 and today's
YNAB from the web and YNAB's help center. No screenshots of real budgets in this repo.

## From YNAB 4

- One month on phones

## From today's YNAB

- Sidebar: bank connections

## Decisions after review round 1

- On phones Zu verteilen lives in a sticky month header; tapping a category opens its sheet (assignment, target,
  rename)

## Budget without inspector (as Actual)

- No inspector column and no filters: overspent categories show Verfügbar in red, its popover covers them
- No income group: income shows only in the month head's calculation
- A category row shows a pencil on hover and focus; it and the name open the category's dialog: the name with its
  emoji as the title, which renames it in place, then target and deleting (the phone sheet: title, Verfügbar,
  target, deleting); there is no cover list or overspent hint in it
- As on the Mac, a mouse drags categories within and between groups and a group as a block between groups;
  "Nicht kategorisiert" stays put, touch does not drag
- Zugewiesen and Aktivität of a category stay blank at 0 (the assign field stays editable); Verfügbar 0 shows
  muted; group rows stay blank at 0 too, only the totals show 0,00. Group rows lie on a quiet band (base-200);
  amounts are never cut off
- Verfügbar is the anchor column: tinted from its title down and semibold; Aktivität is muted. Hovering Zugewiesen
  outlines only the cell under the pointer
- The current month at full contrast, without a label of its own; past months muted (red stays red); later months
  normal
- Verfügbar has no pills: red when overspent, amber with a small ring while the target is underfunded (only in
  months being budgeted: the current one and any other with money assigned; elsewhere plain), a green check for a
  funded target, a grey pause while snoozed, else plain. The marks stand behind the number in a slot every Verfügbar
  figure keeps, so the digits line up in every row. The ring fills by the share of the month's need
  that is assigned, rounded down (25,00 of 40,00 € is 62 %). Only an overspent Verfügbar is a button: hovered like an
  editable cell, it opens the cover list for its month, which becomes the focus
- Covering: the list "40,00 € decken aus" (the overspending, a quiet title in line with the rows) has a card with
  Zu verteilen (the inbox symbol, its amount green) while it is above zero, then a card with every category with
  money, the most first: its emoji in a fixed column, the name, its available amount. Rows are 2.25rem with a
  mouse and 44 px on touch, divided from the text on. It is a popover at the red cell, as wide as its content and
  scrolling inside; on phones a bottom sheet of its own. Choosing one moves as much as it holds, up to the
  overspending, and closes the list; there is no amount field and no button. Money moves between categories that
  are not overspent by changing both Zugewiesen
- Covering, "Ziele füllen" and a target's Zuweisen end in a toast with "Rückgängig" ("24,00 € aus Urlaub
  gedeckt.", "Ziele mit 60,00 € gefüllt.", "60,00 € Urlaub zugewiesen."), for about five seconds or until the next
  action. Undoing adds back to each category what the action changed in its Zugewiesen, so what changed since stays
- Zugewiesen and the transaction amount add and subtract: amounts joined by "+" and "−" ("50+20"), worked out from
  left to right when the field is committed. Any other operator or text that is no amount is refused, and nothing is
  saved: „60*2“ ist kein gültiger Betrag. Rechnen geht mit + und −, etwa 50+20. It never breaks inside "+ und −,"
  or before "50+20" (no-break spaces). The field keeps the text and the focus; the message is a bubble at the cell
  (linked by aria-describedby) that breaks between its two sentences, in the phone sheet a red line under the field.
  The budget's amount fields take the full keyboard, as the decimal pad has neither + nor −
- The category's title renames in place (Enter and leaving the field save, Escape puts the name back); the dialog
  shows the target as one block: its rule ("Jedes Jahr bis zum 24. Dezember weitere 300,00 € zurücklegen"); for a
  target by a date a bar (filled by what is saved of its amount, in the status' tone, with a mark where it should
  stand after the month) and under it what is saved in the rule's verb ("75,00 von 300,00 € zurückgelegt", "415,39
  von 3.000,00 € angespart") on the left and the month's status on the right; a monthly target shows only the
  status. The status: "Noch 100,00 € im November", "Im Plan" (by a date), "Erfüllt", "Überzogen um 12,00 €",
  "Pausiert im November"; no percentage. "100,00 € zuweisen" (the amount it assigns: at most what Zu verteilen
  holds, hidden at zero) leads the target's buttons. Spending a funded target leaves it funded
- A month head is one flat block above its columns: the month and a ghost ⋮ ("Verteilen"), then "Zu verteilen"
  as a tinted row (base-200; a green band above zero in an open month) with its chevron on the left and the amount
  on the right (green above zero, red below, plain at zero; a past month: "Nicht verteilt am Monatsende", muted and
  smaller), then the column titles with their totals; no popover. The corner keeps "Kategorie" and "+ Gruppe" and
  is as tall as the month head. The Mac has the same head, ⋮ instead of ⚡
- Verteilen (⋮), always there: "Ziele füllen" (target) with the amount it moves under it ("68,34 €"), the month's
  underfunded total up to what Zu verteilen holds, and "Zurücksetzen" (rotate-ccw, red) with "Zuweisungen im Okt"
  under it, after "Alle Zuweisungen im Oktober zurücksetzen?" · "Zu verteilen bekommt das Geld zurück." ·
  Zurücksetzen. An item that cannot run is dimmed with the reason under it instead: "Nichts unterfinanziert" (before
  "Nichts zu verteilen"), "Nichts zugewiesen"
- Zu verteilen shows and hides YNAB 4's calculation in every shown month at once, per device (collapsed by
  default, on the Mac too): between the month and Zu verteilen, on a base-200 band between hairlines, the amount
  right-aligned in its column, then the text: "5.947,86 € Nicht verteilt im Sep", "0,00 € Überzogen im Sep",
  "+255,00 € Einnahmen im Okt", "−5.915,41 € Zugewiesen im Okt", "Für spätere Monate" when not zero in an open
  month; only the lines that add up to Zu verteilen
- On phones the sticky month header has the same parts in the same order, compact: the month with ‹ › and ⋮, the
  calculation, Zu verteilen
- Months follow the budget's width: two from 760 px (a window of about 1100 px with the sidebar), three from
  1110 px (about 1450 px); the category column takes 22 % (224–320 px), the months the rest

## Abakus for iPhone and iPad

- Amounts as the web writes them: a true minus and a no-break space before "€" ("−1.234,56 €"); lists show
  "02.11.", sentences and pickers the full date, never a two-digit year
- One base surface and one elevation in both themes (the system's backgrounds); group bands and the calculation
  lie on the elevation, what surrounds them on the base. Text and tinted fills keep 4.5:1 in both themes; text on
  the accent fill (Abgleichen, "… zuweisen") is the accent's content ink, dark in the dark theme, and a
  selected row keeps its inks on a fill of the shown theme, also after the theme changes
- Sheets: the xmark on the leading side, a prominent checkmark on the trailing side where the sheet commits
  something; the xmark reads "Abbrechen" beside a checkmark that commits, else "Schließen". The system's grouped
  backgrounds, opaque at every detent, a grabber where a sheet has detents. While a sheet is up the dock fades back
  with the dimmed screen
- The month is the screen's title as a title menu ("November 2026 ⌄"); it opens a grid of the year's months (past
  ones muted, only the shown one filled) on the regular material, with the year's arrows and "Heute" as a plain
  button, in the system's disabled style while today's month shows. The budget has no ‹ › and no swipe between
  months. With two or three months the title names the first, and each month head names its own; one month needs no
  month in its head
- Zu verteilen is one tinted block, red below zero, plain at zero. The month menu is an ellipsis button beside
  the month: a glass circle in each of the iPad's month heads, the navigation bar's trailing button on phones. It
  holds "Ziele füllen" with the amount it moves as the subtitle and "Zurücksetzen" in red with "Zuweisungen im
  Nov" (behind the web's confirmation); an item that cannot run is dimmed with its reason as the subtitle
  ("Nichts unterfinanziert", "Nichts zu verteilen", "Nichts zugewiesen"). A group's context menu adds
  categories and folds every group, "Neue Kategoriegruppe" ends the list
- The calculation lies on its band between hairlines, its amounts with "€" on Zu verteilen's trailing edge,
  income with "+" whenever it is not zero
- Phones: the sticky head holds the calculation and Zu verteilen; the iPad's corner beside Zu verteilen stays
  empty; the month head follows the title at standard spacing.
  "Nicht kategorisiert" is a row like a category, its name on the names' edge, and shows Alle Konten in the view
  "Ohne Kategorie"
- Phones: a category with a target has a thin bar (3 pt) under its name, filled by the share of the month's need
  that is assigned (the ring's share) over a faint opaque track that stays visible in dark; amber while underfunded in a month being budgeted, green
  when funded, grey while snoozed or in a closed month, red when overspent. Every bar ends at one edge before the
  widest Verfügbar, so equal shares look equal. It takes the ring's place; the check (whenever the bar is green)
  and the pause stay in the mark slot behind Verfügbar. The iPad keeps the ring. Rows carry no status text
- Separators start at the names' leading edge, past the emoji's fixed column, the same for groups and categories on
  both devices (category names start where their group's name does), and "Neue Kategoriegruppe" puts its "+" in
  that column
- The category's sheet: its title is the name with its emoji in title 3 semibold on a faint capsule that a tap
  renames in place (as Reminders' list info), stronger while editing and never focused on opening, the month under it. "Verfügbar": "Übrig aus Vormonat", "Zugewiesen im Nov" (the field), "Aktivität im
  Nov", "Verfügbar" bold in its state colour; there is no cover list and no overspent hint. "Ziel": the web's
  target block (rule; for a target by a date the bar with its mark, then what is saved and the month's status,
  stacked where one line does not fit; else only the status) in a card tinted by the status, the tint inset in its
  row with the card's padding, "68,34 € zuweisen" while something is missing and Zu verteilen has money (at most
  what it holds), then "Ziel bearbeiten" and "Pausieren". Then "Kategorie löschen" in red. Every
  action applies at once, so the sheet only closes. Sheet and popover lie on the grouped background with an opaque
  bar, so neither the budget nor scrolled text shows through. It opens at a detent that shows Verfügbar and Ziel; a
  group's and a new category's sheet open large. On the iPad the same view with the same row surfaces is a popover
  from Verfügbar's trailing side (a tapped name opens it on the month in focus), as tall as its content up to the
  screen and scrolling beyond, without the xmark, and the dock gives way while it shows
- Covering: an overspent Verfügbar opens only the cover list, the web's "40,00 € decken aus" with Zu verteilen's
  card and the categories with money, rows 44 pt. On phones it is a sheet of its own at half height, on the iPad a
  popover at the red cell, as wide as its content, never taller than the screen leaves and scrolling inside. A tap
  on a source covers as much as it holds and closes the list
- Covering, "Ziele füllen" and a target's Zuweisen end in a glass banner above the dock with the web's
  sentence ("25,00 € aus „Zu verteilen“ gedeckt.") and "Rückgängig", a success haptic and a VoiceOver
  announcement, for five seconds or until the next change; leaving the budget ends it. While a category's sheet or
  popover is open the banner stands at its bottom, so one tap reaches it
- A refused amount keeps its text and the focus, again on every refusal, and says the web's sentence inline: in
  the iPad table a bubble below the cell, red text in the Mac's popover chrome; in the sheet a red line under the
  field. VoiceOver announces it
- iPad: Verfügbar's tint is one column from its title down to the bottom of the screen, through the group bands and
  the space above the dock; the mark slot sits inside it.
  Column titles are footnote size in the secondary colour. A month needs 260 pt beside the category column (more
  with larger text), which gives two months from 800 pt and three from 1110 pt of the screen's width
- One navigation in every width, the iPad without a sidebar: a glass tab bar drawn by the app (Budget, Konten,
  Einstellungen; the shown tab's symbol filled, "gearshape" for the settings) with a round glass "+" of its own
  beside it, together at most 440 pt wide and centred. It has the tab bar's traits and the Large Content Viewer,
  shrinks to a circle with the shown tab while scrolling down and comes back on scrolling up, at the top or on a tap
  (never under VoiceOver), stays behind the on-screen keyboard and gives way to the bars of "Auswählen" and of
  reconciling and to the iPad's category popover. Every scrolling root ends its content the dock's height above the safe area, so the last row scrolls
  clear of it, and content fades under the dock and those bars (the soft scroll-edge effect). Konten's badge counts
  what waits for approval; Einstellungen never shows the sync state as its symbol, only a red dot while the owner
  has to act (an error, signed out in the web). ⌘B and ⌘T switch tabs, ⌘, shows the settings, and the app opens on the tab last shown, the
  first time on the budget
- Tab roots have inline titles, as the budget's month menu needs one
- Labels end without the Mac's dialog ellipsis ("Konto bearbeiten", "Einstellungen", "Neue Kategorie"), in menus,
  buttons and the iPad's keyboard menu bar; an ellipsis that means "in progress" stays
- "Neue Buchung" from everywhere: the dock's "+", a plain button. It opens the transaction sheet on the shown
  register's account, else the one last used, with "Sichern und weitere"; ⌘N does the same from every screen
- Konten: the approval row and Alle Konten, then the groups with their totals and an accent chevron that folds them;
  each account pushes its register. An account shows the emoji of its name, else its motif as an SF Symbol
  (building.columns, eurosign.circle for the piggy bank, banknote, chart.line.uptrend.xyaxis, receipt), then the
  balance in the primary ink (red below zero; group totals stay secondary), the symbols in one fixed column so the
  names line up. Badges pair a symbol with the count in the register's chip colours: "?" amber for a missing category, "✓"
  accent for approval, "⚠" red for an error. "N Buchungen bestätigen" has a chevron like "Alle Konten". "+ Konto"
  in the navigation bar adds an account. Konten, Einstellungen and Empfänger keep 720 pt, centred, on the iPad's
  width
- Einstellungen: the labelled field "Server" with the short explanation as its footer, a full-width "Anmelden" in
  the accent whose fill fades to 40 % under a white label in both themes (never grey) while the field is empty, then the sync status with
  "Abmelden", then "Empfänger" as a row that pushes the payees, and "Info" last with the app's version
- Empfänger: the listed payees by initial under compact headers (the initial small and secondary, tight above its
  first name) with a section index ("#" last for names without a
  letter), a search field always in view under the title, a filter for Aufgeführte, Ausgeblendete or Alle (hidden
  ones then muted with an eye-slash) and "Auswählen" as separate bar items, and "Optionen" last with the three
  Ergänzen toggles and a footer that explains them. The title stays centred, so filter and
  "Auswählen" are symbols ("Fertig" a checkmark while picking). Pushed from the settings they close when another
  tab shows or a new transaction starts; from a register they are a sheet with the xmark
- Register header: the balances, each operator with one spacing on both sides however wide the titles above the
  amounts are, then "Abgeglichen am 28.09." in full with "Abgleichen" as the one filled button beside
  it, then what waits as chips, all but the chip of the view shown, also while a search filters the list. A view
  other than Alle Buchungen is named above them ("Ansicht: ohne Kategorie") with "Alle Buchungen" to go back. The
  toolbar holds the search and "Ansicht" (⋯) after it; the phone keeps the search field in view under the title, as
  it shows the filter, the iPad has it in the bar with the title leading in every state. "Ansicht" has short labels
  that never wrap, each with a symbol so all share one leading edge: the four views (list.bullet, checkmark.seal,
  clock, tag.slash) with the system's check mark before the shown one; then "Geplante Buchungen"
  (calendar.badge.clock) while nothing is planned, Auswählen and on the iPad "Memo ausblenden" or "Memo zeigen"; then
  "Konto bearbeiten" (pencil) while it shows one account, the only way to edit an account, and in Alle Konten
  "Geschlossene Konten (n)" (archivebox) while there are any. No label ends in "…". Header and footer lie on the
  screen's own surface; the header is opaque, so scrolled rows never show through it
- Search: the field filters as it is typed, as described under Register
- Phone cards are always two lines after one glyph column that belongs to the second line (the category's emoji, ⚠,
  a split's square.split.2x1, else blank; ⇄ always follows the payee on the first line, only a split's transfer
  part, which has no first line, puts it in the column), so payees and second lines share one leading edge and the
  glyphs one row: payee and
  Betrag, then "Lebensmittel · Memo" and the date. A transfer shows its memo, or "Umbuchung" without one. Every row
  has the regular weight; only the filled ✓ marks one waiting for approval. The month heading sticks on a quiet band
- Status at rest is a small grey glyph (○ vorgemerkt, ✓ gebucht, 🔒 abgeglichen); only a transaction waiting for
  approval shows a filled accent ✓, which approves it. A tap on ○ or ✓ switches between vorgemerkt and gebucht; the
  lock asks "Diese Buchung ist abgeglichen. Entsperren?" first. The only swipe is the trailing "Löschen"
- Approving: the "bestätigen" chip shows the account in the view "Zu bestätigen"; the Konten list's "N Buchungen
  bestätigen" row (which the Konten tab's badge counts) shows Alle Konten in it. The header's line "N Buchungen warten
  auf Bestätigung." has "Alle bestätigen" in place of the reconcile line; once nothing waits, the list reads "Keine
  Buchungen in „Zu bestätigen“", as every empty view names itself. There is no screen of its own, and the UI never
  says "Erinnerung"
- "Auswählen": the title counts ("2 ausgewählt"), "Alle" (⌘A) and "Fertig" sit in the navigation bar, and a bottom bar
  with labelled actions (Kategorie, Löschen in red, ⋯) takes the tab bar's place. On the iPad the column headers move with the selection circles, so they stay over their
  columns
- Reconciling: the header names what the list shows ("20 Buchungen bis 02.11.2026"); a glass bar takes the dock's
  place with the bank's balance as its first line ("Banksaldo 5.428,00 € am 02.11.2026", a tap changes
  it), then "Differenz zur Bank", whose tap opens the calculation and its explanation, and "Abgleichen". The
  calculation writes each operator a single space before its amount, as one text, so an amount wrapped under its
  label starts at the edge
- iPad table: the status column is centred under its header glyph, the first month heading follows the column
  header directly; Empfänger takes the largest text share and the memo the smallest, and a long payee truncates in
  the middle; a split shows its square.split.2x1
- The transaction sheet: the amount first, large, with tabular digits and "€", the −/+ button right before it in the
  accent ("Ausgabe"/"Einnahme"), focused for a new transaction; then Empfänger, Kategorie ("🛒 Lebensmittel", a
  transfer "⇄ Tagesgeld" with no category row between budget accounts), Konto, Datum (full date), Memo, each
  labelled; an empty choice reads "Wählen", a value that cannot change is secondary. A stored transaction ends with
  "Buchung löschen" in red, which deletes it, closes the sheet and offers "Widerrufen".
  "Sichern und weitere" is a bordered button in the footer of the form's last card.
  Above the on-screen keyboard only + − and the keyboard-dismiss button at one size, inside the sheet; a hardware
  keyboard shows none of them. The iPad types the amount on the docked keyboard's numbers, as its floating number
  pad has no operators and covers the sheet's title and bar. The toolbar's checkmark is the one commit, labelled
  "Bestätigen" while the transaction waits, so saving approves it. A refused amount keeps its text and the focus and
  shows Zugewiesen's message under the amount in red, on the iPad as the bubble below it; leaving its page for
  another puts the stored amount back. On the iPad the sheet fits its content
- Pickers: groups are compact section headers without separators, their emoji at the rows' size in the same fixed
  column, so every name starts at one edge ("Einnahmen" too); every row keeps the check's place, so names and
  amounts never shift
- Splits: "Teile" lists each part as "category · amount", opening its own page; a swipe deletes, "Teil hinzufügen"
  follows the last part, "Noch aufzuteilen" sticks under the form on the bar material with a hairline, its text on
  the rows' leading edge, and the form's end scrolls clear of it; the form fades out just above the bar, so no
  card's edge peeks over it. The category reads "Aufgeteilt (2)"
- Geplante Buchungen: an inset list with the register's amount style, "Keine geplanten Buchungen" when empty on the
  list's own background; on the phone a medium detent while the list is short, on the iPad a sheet fitted to its
  rows. Jetzt buchen, Überspringen and Löschen are swipes and the row's context menu; "+" is the only way to add
  one. Its sheet has the web's fields as grouped rows, "Alle 2 Wochen" opening a two-column wheel like the
  Calendar's (the number, Wochen or Monate), and "Löschen …" as a block of its own at the bottom
- Without a sign-in only the sign-in screen shows: Abakus, a line that the budget lives on the user's Abakus server,
  the server field and "Anmelden"; signing out returns to it

## Register

- The header in two rows, web and Mac: the account's name, last reconcile and the pencil on the left, the balances
  ("Gebucht + Vorgemerkt = Arbeitssaldo") and "Abgleichen" (the page's only primary button) on the right; below,
  the toolbar with "Buchung", "Datei-Import" and what waits as chips ("2 bestätigen", "1 zuordnen"), then "Ansicht"
  and the search. The web also names the account's kind; the Mac has no file import.
  Phones: the balances in one line, "2 bestätigen", search and "Ansicht", "Buchung" as the "+" beside the tab bar
- Newest first on both platforms, under a quiet month heading ("Oktober 2026", no total) that sticks while the list
  scrolls; rows then read "24.10.". Headings show only while the list is sorted by date (the web always is)
- Fixed columns, so an opened row keeps every column in place: Betrag fits "−10.000,00", the memo takes the
  remaining width and is hidden per device from "Ansicht"; the column header sticks while the list scrolls. Betrag
  is signed, also for parts: "−88,12" in the normal ink, an inflow "+3.180,00" in green. Editing, each side has one
  amount behind a −/+ button; a click or a sign typed in front sets the direction, a new transaction starts as an
  outflow. With a sign in front the amount's result is signed and sets the direction ("−50+20" is an outflow of
  30,00), without one it goes in the button's direction and a negative result turns the button round ("50−70"
  behind − is an inflow of 20,00)
- The category with its emoji only ("🛒 Lebensmittel"), also in the phone cards; its group shows in the tooltip and
  the picker. What "Ohne Kategorie" lists reads "⚠ Kategorie fehlt", a split on the part that needs one; a
  transfer "⇄ Depot", a split "Aufgeteilt (2)"
- One status column, last, as in Actual: ○ vorgemerkt, ✓ gebucht, 🔒 abgeglichen; a transaction waiting for approval
  shows its ✓ to approve there. Selection is a row highlight, not a column: ⌘ or Ctrl adds a row, Shift the rows up
  to it; on the web "Auswählen" in "Ansicht" makes every click add one (touch screens) and "Alle auswählen" takes
  the whole view. An opened row has Abbrechen and Speichern below it
- Approving on the web: one transaction with its ✓, or by saving it in the row editor or the sheet (✓
  "Bestätigen"). The chip "2 bestätigen" opens the view "Zu bestätigen", ends the search and approves nothing; the
  chip hides there. That view has the line "2 Buchungen warten auf Bestätigung." with "Alle bestätigen", which
  approves what the view shows (as a search typed there narrows it, loaded or not) and leaves match proposals open.
  The selection bar categorises and deletes; deleting asks first, as the web has no undo. The web has no context
  menu
- Views on the web, in "Ansicht" (⋮ on phones): Alle Buchungen, Zu bestätigen, Vorgemerkt, Ohne Kategorie. Each is
  a rule of its own, so a transaction can be in two: "Zu bestätigen" holds every transaction not approved, "Ohne
  Kategorie" every one that needs a category, approved or not: in a budget account, no category, not zero and no
  transfer to another budget account; a split by its parts. The budget's "Nicht kategorisiert" opens Alle Konten
  in that view. "Ansicht" ends with "Empfänger verwalten …", which opens on the selected transaction's payee
- Search and views in the apps, as on the web: the search filters as it is typed and finds payee, category, memo,
  the amount as written ("48,75") and a split's parts, ignoring case, emoji and "ß" against "ss"; a split found by
  a part opens. The views are the web's rules, so the chips and the Konten list count what their
  view lists. The view filters first, the text narrows it; each account keeps its own for the
  session. "Ansicht" holds the four views with a check mark, the Mac's button then reads "Ansicht: zu bestätigen",
  then "Geplante Buchungen" while nothing is planned, on the Mac Status and Memo, which show or hide in every
  account, and in Alle Konten "Geschlossene Konten (n) …". The chips switch views and end the search,
  and only the chip of the view shown hides: "N bestätigen" to Zu bestätigen, "N braucht eine Kategorie" to Ohne
  Kategorie; "Umbuchung mit Kategorie" only tells. While reconciling the list stays Alle Buchungen: "Ansicht"
  leaves out the views and the chips only tell. Zu bestätigen shows "N Buchungen warten auf Bestätigung." with
  "Alle bestätigen" above the list, which approves what the view shows; a search's hit count and "Suche
  zurücksetzen" follow below
- One way each in the apps. A single transaction is approved with its ✓ or by saving it in the editor, whose one
  approving button reads "Bestätigen" (the Mac row editor: "Bestätigen" and "Abbrechen", Return approves only the
  open transaction; the sheet: its ✓). Only the status mark switches vorgemerkt and gebucht; the ✓ and the status
  mark act on their own row, also within a selection, and the open Mac row leaves the status cell empty. The
  context menu (right-click on the Mac, a long press on iOS) holds "Kategorisieren als", "In Konto verschieben"
  and "Löschen" (red on iOS); payees are renamed in "Empfänger verwalten" (⌘Y, Einstellungen) and the editor's
  rename question. The menu "Buchungen" holds "Neue Buchung" (⌘N) and "Suchen" (⌘F). A transfer is a new
  transaction with an account picked as its payee. Every delete (context menu, swipe, the selection bar, the sheet,
  the Delete key) happens at once with "Buchung gelöscht · Widerrufen"; only a reconciled transaction or
  counterpart, one the Kasse or the Depot leads, a transfer whose other side goes too or a transfer into a split asks
  first
- The apps' transaction amounts, parts included, refuse an amount that reads as none as Zugewiesen does: no dialog,
  the text and the focus stay, VoiceOver announces the message once, any edit clears it and saving waits for it; a
  bubble below the field on the Mac and the iPad, a red line under the amount on the iPhone
- The web's transaction amounts (row, sheet, parts) take the full keyboard, as Zugewiesen does, and refuse an amount
  that reads as none or lies beyond the Ledger's range as the field is left and on saving, with Zugewiesen's
  messages, quoting the text as typed: a bubble at the field in the row, a red line under it in the sheet. The text
  and the focus stay, typing in the field clears the message, nothing is saved

## Accounts and scheduled transactions

One form pattern per platform, the same fields in the same order: on the web Setzkasten dialogs (a sheet on
phones) with the label above the field and short fields side by side, on the Mac a sheet (or a popover at the
sidebar row) with one grouped block of label-left rows and capsule buttons, on iPhone and iPad a sheet with grouped
rows. A destructive action ("Konto schließen …", "Löschen …") is a red text button on the left of the footer (web,
Mac) or a block of its own at the bottom (iOS), and asks once.

- "Konto hinzufügen": Name, then Art and "Aktueller Saldo" side by side, the hint "Tracking-Konten zählen nicht zum
  Budget. Das lässt sich später nicht ändern.", Abbrechen and Hinzufügen. The balance may add and subtract like any
  amount and is booked today as the hidden payee "Anfangssaldo", cleared and approved, in a budget account to Zu
  verteilen; 0 books nothing
- "Konto bearbeiten": Name and Art (on the account's side of the budget), "Konto schließen …" asking "Konto „Giro“
  schließen?" with the balance left, if any. Closing leaves the account on screen. One way per platform: the pencil
  beside the name (web), a right click on the sidebar row (Mac), the register's "…" menu (iOS)
- Closed accounts stay out of the sidebar and the account list; Alle Konten's Ansicht menu has "Geschlossene Konten
  (n) …" ("Geschlossene Konten (n)" on iOS) while there are any, a small list with name, kind and balance whose rows
  open the register. A closed account's register says "Dieses Konto ist geschlossen." with "Wieder öffnen" at the top and offers no new
  transaction, no file import and no reconciling. A portfolio's cash, which no register shows, is closed and opened
  again in the Depot's settings
- The Kasse account takes no manual entry anywhere: no "+ Buchung" in its register, never the account of a new
  transaction or scheduled transaction, no reconciling; transfers into it from other accounts stay
- Scheduled transactions sit above the register's transactions as "Geplant · 3", collapsed, for the account or for
  Alle Konten, only while something is planned; Ansicht › "Geplante Buchungen" shows the empty list ("Keine geplanten
  Buchungen" · "Wiederkehrende und künftige Buchungen erscheinen hier.") with "+ Geplante Buchung". A row reads like a
  phone card: the payee (a transfer "⇄ Tagesgeld"), then next date, category and repeat ("Monatlich", "Alle 2
  Wochen"), the amount, with "Jetzt buchen" (approved, as the night would enter it) and "Überspringen"; a click opens
  the dialog
- "Geplante Buchung": Konto and Betrag, Empfänger (transfers as in the register), Kategorie and Memo, a split's parts
  as the transaction sheet has them; below a rule Nächstes Datum and Wiederholen (Einmalig, Monatlich, Jährlich,
  Eigene). Eigene adds "Alle" with a number from 1 to 99 and Wochen or Monate, a segmented control on the web and the
  Mac, a select on the web's phone layout. "Danach: 23.12.2026 · 06.01.2027 · 20.01.2027" follows every change. Errors
  stand at their field. The Mac opens it with a double click on a row

## Icons

Setzkasten's rule: plush images (`AbakusWeb.Plush`, one WebP per motif in `priv/static/images/plush`) for the
sidebar, dock and area switch, the settings hub, empty-state figures, Kasse categories, Depot booking rows and
portfolio rows; Lucide for actions, status, warnings and chevrons. In the sidebar accounts show the
emoji of their name, one without the plush of `AbakusWeb.AccountMotif` (receipt for the shared-expenses account,
else by kind: landmark, piggy-bank, banknote, trending-up); a portfolio without emoji
shows the briefcase. One motif per meaning, e.g. wallet for the budget and cash bookings, landmark for accounts,
briefcase for portfolios and holdings, layers for securities and their trades, coins for dividends and interest,
file-text for receipts, clipboard-list for the empty booking list.

## Method

Every euro gets assigned and overspending is dealt with: RTA > 0 and overspent categories are open tasks, RTA =
0 with nothing overspent is the resting state.

## Review

Two art-director subagents rate every screen 1–10 with concrete feedback, per theme (light, dark), desktop (3, 2, 1 months) and phone (390 px):

- AD A, material/craft: Setzkasten fit, typography, spacing, numbers, details
- AD B, UI/product: hierarchy, familiarity for YNAB/Actual users, task flow, mobile, dark contrast

Both get the reference screenshots and the brief "steal the best from all three".

Round 1 is exploration, not polish: avoid a local maximum. The ADs say what is missing, what the references do
better, and where the screens should ideally go (direction, bigger structural changes, alternatives worth
trying), with a first score only as a baseline. The direction is agreed before polishing. From round 2 they rate
and say what is missing for 9.5. After every round the owner gets a score table with the history. Stop at 9.5.

Status 2026-10-08: seven rounds, both ADs at 9.5 or higher on every screen in light and dark (desktop 1100–1920
with full and collapsed sidebar, phone 390 px).

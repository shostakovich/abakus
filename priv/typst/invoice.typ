// An invoice after DIN 5008, form B. Abakus.Bookkeeping.InvoicePdf writes invoice.json and factur-x.xml beside it.
#let data = json("invoice.json")

#set document(
  title: data.title,
  author: data.sender,
  date: datetime(year: data.date.year, month: data.date.month, day: data.date.day),
)

#set text(lang: "de", size: 10pt)

#set page(
  paper: "a4",
  margin: (left: 25mm, right: 20mm, top: 27mm, bottom: 35mm),
  footer: {
    set text(size: 7.5pt, fill: luma(80))
    line(length: 100%, stroke: 0.4pt + luma(160))
    grid(
      columns: (1fr,) * data.footer.len(),
      column-gutter: 6mm,
      ..data.footer.map(column => column.map(row => [#row]).join(linebreak())),
    )
  },
)

#pdf.attach(
  "factur-x.xml",
  relationship: "alternative",
  mime-type: "text/xml",
  description: "Factur-X/ZUGFeRD-Rechnung",
)

#align(right, text(size: 14pt, weight: "bold", data.sender))

#place(top + left, dy: 30mm, block(width: 85mm, {
  text(size: 7pt, data.return_address)
  v(2mm)
  data.recipient.map(row => [#row]).join(linebreak())
}))

#place(top + left, dx: 100mm, dy: 18mm, block(width: 65mm, grid(
  columns: (auto, 1fr),
  column-gutter: 4mm,
  row-gutter: 2mm,
  ..data.info.map(row => (text(fill: luma(80), row.at(0)), align(right, row.at(1)))).flatten(),
)))

#v(71mm)

#text(size: 12pt, weight: "bold", data.title)

#v(6mm)

#table(
  columns: (8mm, 1fr, auto, auto, auto),
  align: (left, left, right, right, right),
  inset: (x: 4pt, y: 5pt),
  stroke: (x, y) => if y == 0 { (bottom: 0.5pt) } else { (bottom: 0.3pt + luma(200)) },
  table.header([*Pos.*], [*Leistung*], [*Menge*], [*Einzelpreis*], [*Betrag*]),
  ..data.positions.map(row => row.map(cell => [#cell])).flatten(),
)

#v(4mm)

#align(right, grid(
  columns: (auto, 32mm),
  column-gutter: 6mm,
  row-gutter: 3mm,
  align: (left, right),
  ..data.totals.map(row => if row.strong { (strong(row.label), strong(row.amount)) } else { (row.label, row.amount) }).flatten(),
))

#v(8mm)

#for note in data.notes {
  par(note)
}

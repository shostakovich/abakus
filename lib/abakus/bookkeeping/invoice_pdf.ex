defmodule Abakus.Bookkeeping.InvoicePdf do
  @moduledoc """
  An invoice's PDF: Typst sets `priv/typst/invoice.typ`, a plain letter after DIN 5008, as PDF/A-3 with the
  e-invoice (`Abakus.Bookkeeping.EInvoice`) attached, which makes it a ZUGFeRD invoice. Typst is part of the image,
  like poppler's `pdftotext`. The template gets the invoice as text already written out, so that it only lays out.
  """

  require Logger

  alias Abakus.Bookkeeping.{Countries, EInvoice, Invoice, Party, Position}
  alias Abakus.{Format, Money}

  @doc "The PDF's file name: `Rechnung 2027126.pdf`."
  def filename(%Invoice{number: number}), do: "Rechnung #{number}.pdf"

  def render(%Invoice{} = invoice) do
    case System.find_executable("typst") do
      nil ->
        Logger.warning("typst is missing, invoices cannot be rendered")
        :error

      typst ->
        in_tmp_dir(&compile(typst, &1, invoice))
    end
  end

  defp compile(typst, dir, invoice) do
    File.cp!(
      Application.app_dir(:abakus, "priv/typst/invoice.typ"),
      Path.join(dir, "invoice.typ")
    )

    File.write!(Path.join(dir, "invoice.json"), JSON.encode!(data(invoice)))
    File.write!(Path.join(dir, EInvoice.filename()), EInvoice.xml(invoice))

    args =
      ~w(compile --pdf-standard a-3b --ignore-system-fonts --root) ++
        [dir, "invoice.typ", "invoice.pdf"]

    case System.cmd(typst, args, cd: dir, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, File.read!(Path.join(dir, "invoice.pdf"))}

      {output, status} ->
        Logger.error("typst failed with #{status}: #{output}")
        :error
    end
  end

  defp in_tmp_dir(fun) do
    dir = Path.join(System.tmp_dir!(), "abakus-invoice-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      fun.(dir)
    after
      File.rm_rf!(dir)
    end
  end

  @doc "What the template shows, as text."
  def data(%Invoice{} = invoice) do
    %{
      title: "Rechnung #{invoice.number}",
      date: %{year: invoice.date.year, month: invoice.date.month, day: invoice.date.day},
      sender: invoice.sender.name,
      return_address: Enum.join([invoice.sender.name | address(invoice.sender)], " · "),
      recipient: [invoice.recipient.name | address(invoice.recipient)],
      info: info(invoice),
      positions: Enum.with_index(invoice.positions, 1) |> Enum.map(&position/1),
      totals: totals(invoice),
      notes: notes(invoice),
      footer: footer(invoice.sender)
    }
  end

  defp address(%Party{} = party) do
    country =
      if party.country != "DE", do: [String.upcase(Countries.name(party.country))], else: []

    [party.street, "#{party.postal_code} #{party.city}"] ++ country
  end

  defp info(invoice) do
    [
      ["Rechnungsnummer", invoice.number],
      ["Rechnungsdatum", Format.date(invoice.date)],
      [period_label(invoice), period(invoice)],
      present?(invoice.recipient.vat_id) && ["Ihre USt-IdNr.", invoice.recipient.vat_id]
    ]
    |> Enum.filter(& &1)
  end

  defp period_label(%{service_from: day, service_to: day}), do: "Leistungsdatum"
  defp period_label(_invoice), do: "Leistungszeitraum"

  defp period(%{service_from: day, service_to: day}), do: Format.date(day)

  defp period(invoice),
    do: "#{Format.date(invoice.service_from)} – #{Format.date(invoice.service_to)}"

  defp position({%Position{} = position, index}) do
    [
      Integer.to_string(index),
      position.description,
      "#{Format.decimal(position.quantity)} #{Position.unit_short(position.unit)}",
      Money.euros(position.unit_price),
      Money.euros(Position.net(position))
    ]
  end

  defp totals(%Invoice{vat: :reverse_charge} = invoice) do
    [
      %{label: "Nettobetrag", amount: Money.euros(invoice.net), strong: false},
      %{label: "Umsatzsteuer", amount: Money.euros(0), strong: false},
      %{label: "Gesamtbetrag", amount: Money.euros(invoice.total), strong: true}
    ]
  end

  defp totals(invoice) do
    [
      %{label: "Nettobetrag", amount: Money.euros(invoice.net), strong: false},
      %{
        label: "Umsatzsteuer #{Invoice.rate(invoice.vat)} %",
        amount: Money.euros(invoice.vat_amount),
        strong: false
      },
      %{label: "Gesamtbetrag", amount: Money.euros(invoice.total), strong: true}
    ]
  end

  defp notes(invoice) do
    [
      invoice.vat == :reverse_charge &&
        "#{EInvoice.reverse_charge_note()} (Reverse Charge, Art. 196 MwStSystRL).",
      "Bitte überweisen Sie #{Money.euros(invoice.total)} bis zum #{Format.date(invoice.due_date)} " <>
        "auf das Konto #{iban(invoice.sender.iban)} und geben Sie dabei die Rechnungsnummer " <>
        "#{invoice.number} an."
    ]
    |> Enum.filter(& &1)
  end

  defp footer(%Party{} = sender) do
    [
      [sender.name | address(sender)],
      Enum.filter(
        [
          present?(sender.tax_number) && "Steuernummer #{sender.tax_number}",
          present?(sender.vat_id) && "USt-IdNr. #{sender.vat_id}"
        ],
        & &1
      ),
      ["IBAN #{iban(sender.iban)}"]
    ]
  end

  defp iban(iban),
    do: iban |> String.graphemes() |> Enum.chunk_every(4) |> Enum.map_join(" ", &Enum.join/1)

  defp present?(value), do: value not in [nil, ""]
end

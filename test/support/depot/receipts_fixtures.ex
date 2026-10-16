defmodule Abakus.Depot.ReceiptsFixtures do
  @moduledoc "Synthetic receipts, their text and the fake model's answers for tests."

  @doc "The text of a made-up purchase receipt, as `pdftotext -layout` gives it."
  def receipt_text(reference \\ "SP-0001") do
    """
    Musterbank AG                                              Seite 1/1
    Depot 4472
    Wertpapierabrechnung Kauf
    Sparplanausführung vom 01.10.2026
    Wertpapier: VANGUARD FTSE ALL-WORLD U.ETF
    ISIN IE00BK5BQT80
    Stück                 93,207
    Ausführungskurs       12,0699 EUR
    Kurswert              1.125,00 EUR
    Provision             0,00 EUR
    Zu Lasten Konto 0816  1.125,00 EUR
    Referenz #{reference}
    """
  end

  @doc "The model's answer for `receipt_text/1`, with `changes` over its fields."
  def answer(changes \\ %{}) do
    %{
      "kind" => "purchase",
      "date" => "2026-10-01",
      "isin" => "IE00BK5BQT80",
      "security_name" => "Vanguard FTSE All-World U.ETF",
      "shares" => 93.207,
      "price" => 12.0699,
      "fees" => 0,
      "taxes" => nil,
      "amount" => 1125.0,
      "depot_number" => "4472",
      "bank_reference" => "SP-0001"
    }
    |> Map.merge(changes)
    |> JSON.encode!()
  end

  @doc "A PDF file of its own content under `name` in a temporary directory; returns its path."
  def pdf_file(name \\ "beleg.pdf", content \\ nil) do
    dir = Path.join(System.tmp_dir!(), "abakus-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, content || "%PDF-1.4\n% #{System.unique_integer()}\n%%EOF\n")
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(dir) end)
    path
  end

  @doc "Waits until the receipts queued for recognition so far are done."
  def await_recognition do
    :sys.get_state(Abakus.Depot.Receipts.Recognition)
    :ok
  end
end

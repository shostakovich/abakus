defmodule Abakus.Depot.Receipts.PdftotextTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Receipts.Pdftotext

  # Runs only where poppler is installed, as in the image.
  @moduletag :pdftotext

  test "reads the text layer of a PDF" do
    assert {:ok, text} = Pdftotext.text("test/fixtures/depot/receipts/synthetic.pdf")
    assert text =~ "Wertpapierabrechnung Kauf"
    assert text =~ "ISIN IE00BK5BQT80"
  end

  test "fails for a file that is no readable PDF" do
    path = Path.join(System.tmp_dir!(), "abakus-broken-#{System.unique_integer()}.pdf")
    File.write!(path, "%PDF-1.4\n%%EOF\n")
    on_exit(fn -> File.rm(path) end)

    assert Pdftotext.text(path) == :error
  end
end

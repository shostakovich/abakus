defmodule Abakus.EInvoiceSchema do
  @moduledoc "Checks an e-invoice against the XML schema of Factur-X's profile EN 16931, as ZUGFeRD uses it."

  @schema "test/fixtures/bookkeeping/factur-x/Factur-X_EN16931.xsd"

  @doc "The schema's complaints about `xml`, none when it is valid."
  def errors(xml) do
    {:ok, schema} = :xmerl_xsd.process_schema(String.to_charlist(@schema))

    case :xmerl_xsd.validate(parse(xml), schema) do
      {:error, reasons} -> reasons
      {_valid, _state} -> []
    end
  end

  @doc "The texts at an XPath of `xml`."
  def texts(xml, path) do
    for node <- :xmerl_xpath.string(String.to_charlist(path <> "/text()"), parse(xml)),
        do: node |> elem(4) |> List.to_string()
  end

  defp parse(xml) do
    {document, []} =
      xml |> :binary.bin_to_list() |> :xmerl_scan.string(namespace_conformant: true)

    document
  end
end

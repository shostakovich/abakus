defmodule Abakus.Depot.Receipts.TextExtractor do
  @moduledoc "Reads the text layer of a PDF file; `:error` for a file without one."

  @callback text(path :: Path.t()) :: {:ok, String.t()} | :error
end

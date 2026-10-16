defmodule Abakus.Currency do
  @moduledoc "Currency codes as every area stores them."

  @doc ~s(A currency code as stored: `" usd "` is `"USD"`.)
  @spec normalize(String.t()) :: String.t()
  def normalize(currency), do: currency |> String.trim() |> String.upcase()

  @doc "Whether `code` is three ASCII capitals."
  @spec valid?(String.t()) :: boolean()
  def valid?(code), do: code =~ ~r/\A[A-Z]{3}\z/
end

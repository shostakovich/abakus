defmodule Abakus.Depot.Receipts.Model do
  @moduledoc """
  A language model that answers with JSON by a schema (ADR 0015). Not available without its
  configuration; receipts then open an empty form.
  """

  @callback available?() :: boolean

  @doc "What the settings call the model, nil when none is configured."
  @callback name() :: String.t() | nil

  @doc """
  The model's next answer in a chat of `messages`, the receipt's text first; a correction round
  adds the model's answer and the user's reply.
  """
  @callback answer(
              instructions :: String.t(),
              messages :: [{:user | :assistant, String.t()}],
              schema :: map
            ) :: {:ok, String.t()} | {:error, term}
end

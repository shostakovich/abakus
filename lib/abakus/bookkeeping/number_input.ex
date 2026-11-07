defmodule Abakus.Bookkeeping.NumberInput do
  @moduledoc """
  Casts a number as people type it into a form with a parser of `Abakus.Money`: blank text clears the field, text
  the parser cannot read is an error with the given message, and a value that is no text is cast as it is.
  """

  import Ecto.Changeset

  @doc "Casts `field` from `attrs` with `parse`, which returns `{:ok, value}` or `{:error, reason}`."
  def cast_number(changeset, attrs, field, parse, invalid) do
    case attrs[Atom.to_string(field)] || attrs[field] do
      nil ->
        changeset

      text when is_binary(text) ->
        if String.trim(text) == "" do
          put_change(changeset, field, nil)
        else
          put_parsed(changeset, field, parse.(text), invalid)
        end

      value ->
        cast(changeset, %{field => value}, [field])
    end
  end

  @doc "Casts an amount in euros and cents into cents."
  def cast_cents(changeset, attrs, field),
    do: cast_number(changeset, attrs, field, &Abakus.Money.parse(&1, 2), "ist kein Betrag")

  defp put_parsed(changeset, field, {:ok, value}, _invalid),
    do: put_change(changeset, field, value)

  defp put_parsed(changeset, field, {:error, _}, invalid),
    do: add_error(changeset, field, invalid)
end

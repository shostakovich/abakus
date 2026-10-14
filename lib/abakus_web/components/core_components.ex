defmodule AbakusWeb.CoreComponents do
  @moduledoc """
  The app's own helpers next to Setzkasten's components (`use Setzkasten` in `AbakusWeb`): German error messages.
  """

  @doc "German messages from the validation pass through; Ecto's English ones are translated."
  @spec translate_error({String.t(), keyword}) :: String.t()
  def translate_error({msg, opts}) do
    # Errors from database constraints carry `constraint:` instead of `validation:`.
    (Keyword.get(opts, :validation) || Keyword.get(opts, :constraint))
    |> german(msg, opts)
    |> interpolate(opts)
  end

  defp german(:required, "can't be blank", _opts), do: "muss ausgefüllt werden"
  defp german(:format, "has invalid format", _opts), do: "hat ein ungültiges Format"
  defp german(:inclusion, "is invalid", _opts), do: "ist kein gültiger Wert"
  defp german(:subset, "has an invalid entry", _opts), do: "enthält einen ungültigen Eintrag"
  defp german(:exclusion, "is reserved", _opts), do: "ist nicht erlaubt"
  defp german(:acceptance, "must be accepted", _opts), do: "muss akzeptiert werden"
  defp german(:confirmation, "does not match confirmation", _opts), do: "stimmt nicht überein"

  defp german(key, "is invalid", _opts) when key in [:cast, :assoc, :embed, :check],
    do: "ist ungültig"

  defp german(key, "has already been taken", _opts) when key in [:unique, :unsafe_unique],
    do: "ist bereits vergeben"

  defp german(key, "does not exist", _opts) when key in [:foreign, :assoc],
    do: "existiert nicht"

  defp german(:no_assoc, "is still associated with this entry", _opts),
    do: "ist noch mit diesem Eintrag verknüpft"

  defp german(:no_assoc, "are still associated with this entry", _opts),
    do: "sind noch mit diesem Eintrag verknüpft"

  defp german(:number, "must be less than %{number}", _opts),
    do: "muss kleiner als %{number} sein"

  defp german(:number, "must be greater than %{number}", _opts),
    do: "muss größer als %{number} sein"

  defp german(:number, "must be less than or equal to %{number}", _opts),
    do: "darf höchstens %{number} sein"

  defp german(:number, "must be greater than or equal to %{number}", _opts),
    do: "muss mindestens %{number} sein"

  defp german(:number, "must be equal to %{number}", _opts), do: "muss %{number} sein"
  defp german(:number, "must be not equal to %{number}", _opts), do: "darf nicht %{number} sein"

  defp german(:length, "should be at least %{count} character(s)", _opts),
    do: "muss mindestens %{count} Zeichen lang sein"

  defp german(:length, "should be at most %{count} character(s)", _opts),
    do: "darf höchstens %{count} Zeichen lang sein"

  defp german(:length, "should be %{count} character(s)", _opts),
    do: "muss genau %{count} Zeichen lang sein"

  defp german(:length, "should be at least %{count} byte(s)", opts),
    do: "muss mindestens %{count} #{unit(opts, "Byte", "Bytes")} lang sein"

  defp german(:length, "should be at most %{count} byte(s)", opts),
    do: "darf höchstens %{count} #{unit(opts, "Byte", "Bytes")} lang sein"

  defp german(:length, "should be %{count} byte(s)", opts),
    do: "muss genau %{count} #{unit(opts, "Byte", "Bytes")} lang sein"

  defp german(:length, "should have at least %{count} item(s)", opts),
    do: "braucht mindestens %{count} #{unit(opts, "Eintrag", "Einträge")}"

  defp german(:length, "should have at most %{count} item(s)", opts),
    do: "darf höchstens %{count} #{unit(opts, "Eintrag", "Einträge")} haben"

  defp german(:length, "should have %{count} item(s)", opts),
    do: "braucht genau %{count} #{unit(opts, "Eintrag", "Einträge")}"

  defp german(_key, msg, _opts), do: msg

  defp unit(opts, one, many), do: if(opts[:count] == 1, do: one, else: many)

  defp interpolate(msg, opts) do
    Regex.replace(~r/%{(\w+)}/, msg, fn whole, key -> option_text(opts, key, whole) end)
  end

  defp option_text(opts, key, fallback) do
    case Enum.find(opts, fn {name, _} -> Atom.to_string(name) == key end) do
      {_, value} -> to_string(value)
      nil -> fallback
    end
  end
end

defmodule AbakusWeb.Depot.SecurityChanges do
  @moduledoc """
  What saving the edit dialog of a security does beyond its fields, so the dialog can say so
  before: the prices it loads anew or stops fetching, the DivvyDiary data it fetches or removes,
  retiring it or bringing it back, and whether it asks first.
  """

  alias Abakus.Depot.Securities.{ISIN, Security}

  @fund_data "TER, Fondsgröße, Länder, Sektoren und Dividenden"
  @retired "Ausgemusterte Wertpapiere holen keine Kurse und Fondsdaten."

  defstruct source: nil, isin: nil, retired: nil, back: [], held: false, benchmark: false

  @doc """
  The changes `params` (the dialog's, with string keys) make to `security`: `source` is `:new`
  for prices loaded anew from Yahoo, `:stop` when Yahoo stops, `isin` is `:added`, `:changed` or
  `:removed`, `retired` is `:retire` or `:reactivate`; nil for no change. An invalid ISIN changes
  nothing yet. `usage` (see `Securities.usage/2`) says whether retiring leaves holdings or a
  benchmark without prices; `back` is what a reactivated security fetches again.
  """
  def of(%Security{} = security, params, usage \\ %{held: false, benchmark: false}) do
    retired = retired(security.retired, params)

    %__MODULE__{
      source: source(security, params),
      isin: isin(security.isin, params),
      retired: retired,
      back: if(retired == :reactivate, do: fetched_again(security, params), else: []),
      held: usage.held,
      benchmark: usage.benchmark
    }
  end

  defp source(security, params) do
    feed = Map.get(params, "quote_feed", to_string(security.quote_feed))
    symbol = blank_to_nil(Map.get(params, "symbol", security.symbol))

    cond do
      feed == "yahoo" and symbol != nil and
          {security.quote_feed, security.symbol} != {:yahoo, symbol} ->
        :new

      feed == "manual" and security.quote_feed == :yahoo ->
        :stop

      true ->
        nil
    end
  end

  defp isin(before, %{"isin" => typed}) do
    case {blank_to_nil(before), typed_isin(typed)} do
      {same, same} -> nil
      {_before, nil} -> :removed
      {before, isin} -> if ISIN.valid?(isin), do: new_isin(before)
    end
  end

  defp isin(_before, _params), do: nil

  defp new_isin(nil = _before), do: :added
  defp new_isin(_before), do: :changed

  defp retired(true, %{"retired" => "false"}), do: :reactivate
  defp retired(false, %{"retired" => "true"}), do: :retire
  defp retired(_retired, _params), do: nil

  defp fetched_again(security, params) do
    yahoo? = Map.get(params, "quote_feed", to_string(security.quote_feed)) == "yahoo"
    isin? = Map.get(params, "isin", security.isin) |> typed_isin() |> then(&(&1 != nil))
    Enum.filter([prices: yahoo?, fund_data: isin?], &elem(&1, 1)) |> Keyword.keys()
  end

  @doc "A typed ISIN in capitals and without spaces, nil when blank."
  def typed_isin(typed),
    do: (typed || "") |> String.replace(" ", "") |> String.upcase() |> blank_to_nil()

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: String.trim(value)

  @doc """
  The consequence of a changed ISIN as `{text, tone}`, tone `:warning` when saving drops data;
  nil without a change. `available` says whether DivvyDiary has its API key.
  """
  def isin_help(%__MODULE__{isin: :removed}, _available),
    do: {"#{@fund_data} von DivvyDiary werden entfernt.", :warning}

  def isin_help(%__MODULE__{isin: :changed}, true),
    do:
      {"Die Fondsdaten der bisherigen ISIN werden entfernt und neu von DivvyDiary geholt.",
       :warning}

  def isin_help(%__MODULE__{isin: :changed}, false),
    do: {"Die Fondsdaten der bisherigen ISIN werden entfernt.", :warning}

  def isin_help(%__MODULE__{isin: :added}, true),
    do: {"#{@fund_data} werden von DivvyDiary geholt.", nil}

  def isin_help(_changes, _available), do: nil

  @doc "What an ISIN brings from DivvyDiary."
  def fund_data_help, do: "Bringt #{@fund_data} von DivvyDiary."

  @doc "The warning under the prices' source, nil without a change."
  def source_help(%__MODULE__{source: :new}), do: "Die Kurse werden neu von Yahoo geladen."

  def source_help(%__MODULE__{source: :stop}),
    do: "Neue Kurse kommen dann nicht mehr von Yahoo; die bisherigen bleiben."

  def source_help(_changes), do: nil

  @doc """
  The line under Ausgemustert as `{text, tone}`: a warning when retiring leaves holdings or a
  benchmark without new prices, what comes again when it is brought back.
  """
  def retired_help(%__MODULE__{retired: :retire} = changes) do
    case retire_warning(changes) do
      nil -> {@retired, nil}
      warning -> {warning, :warning}
    end
  end

  def retired_help(%__MODULE__{retired: :reactivate, back: [_ | _] = back}),
    do: {"#{back_text(back)} werden wieder geholt.", nil}

  def retired_help(_changes), do: {@retired, nil}

  defp retire_warning(%{held: true, benchmark: true}),
    do: "Noch im Bestand und als Benchmark gewählt: die Kurse bleiben dann stehen."

  defp retire_warning(%{held: true}), do: "Noch im Bestand: die Kurse bleiben dann stehen."

  defp retire_warning(%{benchmark: true}),
    do: "Als Benchmark gewählt: die Kurse bleiben dann stehen."

  defp retire_warning(_changes), do: nil

  defp back_text([:prices, :fund_data]), do: "Kurse und Fondsdaten"
  defp back_text([:prices]), do: "Kurse"
  defp back_text([:fund_data]), do: "Fondsdaten"

  @doc """
  What saving asks first, as `%{question, text, label}` for the confirm dialog: retiring a
  security still held or compared with, removing the ISIN and stopping Yahoo; nil when it saves
  without asking.
  """
  def confirmation(%__MODULE__{retired: :retire} = changes) do
    case retire_warning(changes) do
      nil ->
        confirmation(%{changes | retired: nil, source: nil})

      warning ->
        text =
          if changes.isin == :removed,
            do: "#{warning} #{@fund_data} von DivvyDiary werden gelöscht.",
            else: warning

        %{question: "Wertpapier ausmustern?", text: text, label: "Ausmustern"}
    end
  end

  def confirmation(%__MODULE__{isin: :removed, source: :stop}),
    do: %{
      question: "ISIN entfernen und Kursabruf beenden?",
      text: "#{@fund_data} von DivvyDiary werden gelöscht; die bisherigen Kurse bleiben.",
      label: "Speichern"
    }

  def confirmation(%__MODULE__{isin: :removed}),
    do: %{
      question: "ISIN entfernen?",
      text: "#{@fund_data} von DivvyDiary werden gelöscht.",
      label: "Entfernen"
    }

  def confirmation(%__MODULE__{source: :stop}),
    do: %{
      question: "Kursabruf beenden?",
      text: "Neue Kurse kommen nicht mehr von Yahoo; die bisherigen bleiben.",
      label: "Beenden"
    }

  def confirmation(_changes), do: nil

  @doc """
  What saving asks first when Yahoo says the new ISIN belongs to `other`, clearly another
  security (`other_security/2`): `kept` is the Yahoo symbol the prices keep coming from, nil when
  that changes too; what `confirmation/1` asks adds its text.
  """
  def confirmation(%__MODULE__{} = changes, nil = _other, _kept), do: confirmation(changes)

  def confirmation(%__MODULE__{} = changes, other, kept) do
    asked = confirmation(changes)

    text =
      join_sentences([
        "Laut Yahoo gehört sie zu #{other}" <>
          if(kept, do: "; die Kurse kommen weiter von #{kept}.", else: "."),
        asked && asked.text
      ])

    %{question: "ISIN eines anderen Wertpapiers übernehmen?", text: text, label: "Übernehmen"}
  end

  defp join_sentences(sentences), do: sentences |> Enum.reject(&is_nil/1) |> Enum.join(" ")

  @doc """
  What Yahoo's lookup of a new ISIN says as `{text, tone}`: the name it belongs to, a warning when
  that is clearly another than `name`, or why it found nothing.
  """
  def yahoo_name(:searching, _name), do: {"Suche bei Yahoo …", nil}

  def yahoo_name({:ok, %{name: found}}, name) do
    if same_name?(found, name),
      do: {"Laut Yahoo: #{found}.", nil},
      else: {"Laut Yahoo: #{found}. Ein anderes Wertpapier?", :warning}
  end

  def yahoo_name({:error, message}, _name), do: {message, nil}

  @doc "What Yahoo found for a new ISIN, `%{name, symbol}`, when it is clearly not `name`; else nil."
  def other_security({:ok, %{name: found} = listing}, name),
    do: if(!same_name?(found, name), do: listing)

  def other_security(_result, _name), do: nil

  # The same when most words of the shorter name are in the other: Yahoo adds share classes.
  defp same_name?(a, b) do
    {short, long} = Enum.min_max_by([words(a), words(b)], &MapSet.size/1)
    size = MapSet.size(short)
    size > 0 and MapSet.size(MapSet.intersection(short, long)) * 2 >= size
  end

  defp words(name) do
    name
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> MapSet.new()
  end
end

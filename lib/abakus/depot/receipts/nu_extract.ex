defmodule Abakus.Depot.Receipts.NuExtract do
  @moduledoc """
  NuExtract, an extraction model, as a receipt model for the measurement: the chat API of
  `Abakus.Depot.Receipts.ChatAPI`, but one user message with a template of the fields by
  `Fields.json_schema/0` and the receipt's text as context, its own input format, instead of
  instructions and a schema. Numbers come verbatim, as the app reads them anyway. It cannot
  continue a chat, so a correction round fails and keeps the first answer. The `:prelude` of
  its configuration, if any, goes before the template.
  """
  @behaviour Abakus.Depot.Receipts.Model

  alias Abakus.Depot.MarketData.HTTP
  alias Abakus.Depot.Receipts.{ChatAPI, Fields}

  @impl true
  defdelegate available?, to: ChatAPI

  @impl true
  defdelegate name, to: ChatAPI

  @impl true
  def answer(_instructions, [{:user, text}], schema) do
    config = Application.get_env(:abakus, ChatAPI, [])

    body = %{
      model: config[:model],
      temperature: 0,
      reasoning_effort: "none",
      messages: [%{role: "user", content: prompt(config[:prelude], schema, text)}]
    }

    url = String.trim_trailing(config[:url], "/") <> "/chat/completions"

    with {:ok, 200, response} <- HTTP.post_json(url, body, [], timeout: 300_000),
         {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} <-
           JSON.decode(response) do
      {:ok, answer_json(content, schema)}
    else
      {:ok, status, _response} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_response}
    end
  end

  def answer(_instructions, _chat, _schema), do: {:error, :no_chat}

  defp prompt(prelude, schema, text) do
    template =
      Map.new(schema.properties.pairs, fn
        {name, %{enum: values}} -> {name, values}
        {:date, _property} -> {:date, "date-time"}
        {name, _property} -> {name, "verbatim-string"}
      end)

    ordered = %Fields.OrderedObject{
      pairs: for({name, _property} <- schema.properties.pairs, do: {name, template[name]})
    }

    Enum.join(
      Enum.reject([prelude, "# Template:", JSON.encode!(ordered), "# Context:", text], &is_nil/1),
      "\n"
    )
  end

  # Every field, the date without a time.
  defp answer_json(content, schema) do
    case JSON.decode(String.trim(content)) do
      {:ok, %{} = json} ->
        schema.properties.pairs
        |> Map.new(fn {name, _property} -> {name, json[Atom.to_string(name)]} end)
        |> Map.update!(:date, &date/1)
        |> JSON.encode!()

      _other ->
        content
    end
  end

  defp date(<<day::binary-size(10), "T", _time::binary>>), do: day
  defp date(date), do: date
end

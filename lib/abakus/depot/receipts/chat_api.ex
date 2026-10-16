defmodule Abakus.Depot.Receipts.ChatAPI do
  @moduledoc """
  Any OpenAI-compatible chat API, such as Ollama or LM Studio on the home server: base URL,
  model and an optional key from `RECEIPT_MODEL_URL`, `RECEIPT_MODEL` and `RECEIPT_MODEL_KEY`.
  A thinking model is asked not to think, by `reasoning_effort: "none"`, which both Ollama and
  LM Studio understand, unless `RECEIPT_MODEL_THINKING` is on.
  """
  @behaviour Abakus.Depot.Receipts.Model

  alias Abakus.HTTP

  # A model on the CPU takes about a minute per receipt.
  @timeout 300_000

  @impl true
  def available?, do: present?(config(:url)) and present?(config(:model))

  @impl true
  def name do
    if available?(), do: "#{config(:model)} auf #{URI.parse(config(:url)).host || config(:url)}"
  end

  @impl true
  def answer(instructions, messages, schema) do
    body =
      Map.merge(thinking_options(), %{
        model: config(:model),
        temperature: 0,
        messages: [
          %{role: "system", content: instructions}
          | Enum.map(messages, fn {role, content} -> %{role: role, content: content} end)
        ],
        response_format: %{
          type: "json_schema",
          json_schema: %{name: "receipt", strict: true, schema: schema}
        }
      })

    case HTTP.post(url(), json: body, headers: headers(), timeout: @timeout) do
      {:ok, 200, response} -> content(response)
      {:ok, status, _response} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp thinking_options, do: if(config(:thinking), do: %{}, else: %{reasoning_effort: "none"})

  defp url, do: String.trim_trailing(config(:url), "/") <> "/chat/completions"

  defp headers do
    if present?(config(:api_key)),
      do: [{"authorization", "Bearer " <> config(:api_key)}],
      else: []
  end

  # LM Studio puts a thinking model's constrained answer into `reasoning_content`.
  defp content(response) do
    with {:ok, %{"choices" => [%{"message" => message} | _]}} <- JSON.decode(response),
         answer when is_binary(answer) <- answer(message) do
      {:ok, answer}
    else
      _other -> {:error, :invalid_response}
    end
  end

  defp answer(%{"content" => content} = message) when content in [nil, ""],
    do: message["reasoning_content"]

  defp answer(%{"content" => content}), do: content
  defp answer(_message), do: nil

  defp present?(value), do: value not in [nil, ""]

  defp config(key), do: Application.get_env(:abakus, __MODULE__, [])[key]
end

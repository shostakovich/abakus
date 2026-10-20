defmodule Abakus.BankSync.EnableBanking do
  @moduledoc """
  Enable Banking's API (ADR 0020), as the application `ENABLE_BANKING_APP_ID` with the private key in the file
  `ENABLE_BANKING_KEY_FILE`; each request carries a fresh `Abakus.BankSync.JWT`. Personal accounts only.
  """
  @behaviour Abakus.BankSync.Client

  alias Abakus.BankSync.JWT
  alias Abakus.HTTP

  @base_url "https://api.enablebanking.com"
  @timeout 30_000

  @impl true
  def available?, do: config(:app_id) != nil and config(:key_file) != nil

  @impl true
  def banks(country) do
    case request(:get, "/aspsps", params: [country: country, psu_type: "personal"]) do
      {:ok, %{"aspsps" => aspsps}} when is_list(aspsps) ->
        {:ok, for(aspsp <- aspsps, personal?(aspsp), do: bank(aspsp))}

      {:ok, _other} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp personal?(aspsp), do: "personal" in Map.get(aspsp, "psu_types", ["personal"])

  defp bank(aspsp) do
    %{
      name: aspsp["name"],
      country: aspsp["country"],
      maximum_consent_validity: aspsp["maximum_consent_validity"]
    }
  end

  @impl true
  def start_auth(request) do
    body = %{
      access: %{valid_until: DateTime.to_iso8601(request.valid_until)},
      aspsp: request.bank,
      state: request.state,
      redirect_url: request.redirect_url,
      psu_type: "personal"
    }

    case request(:post, "/auth", json: body) do
      {:ok, %{"url" => "https://" <> _rest = url}} -> {:ok, url}
      {:ok, _other} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def create_session(code) do
    case request(:post, "/sessions", json: %{code: code}) do
      {:ok, %{"session_id" => session_id, "accounts" => accounts} = session}
      when is_binary(session_id) and is_list(accounts) ->
        {:ok,
         %{
           session_id: session_id,
           valid_until: valid_until(session["access"]),
           accounts: Enum.map(accounts, &account/1)
         }}

      {:ok, _other} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_until(%{"valid_until" => text}) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, moment, _offset} -> moment
      {:error, _reason} -> nil
    end
  end

  defp valid_until(_access), do: nil

  defp account(account) do
    %{
      uid: account["uid"],
      name: account["name"] || account["product"],
      iban: get_in(account, ["account_id", "iban"])
    }
  end

  defp request(method, path, opts) do
    with {:ok, token} <- token(),
         opts = [headers: [{"authorization", "Bearer " <> token}], timeout: @timeout] ++ opts,
         {:ok, status, body} <- send_request(method, base_url() <> path, opts) do
      decode(status, body)
    end
  end

  defp send_request(:get, url, opts), do: HTTP.get(url, opts)
  defp send_request(:post, url, opts), do: HTTP.post(url, opts)

  defp decode(status, body) when status in 200..299 do
    case JSON.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :invalid_response}
    end
  end

  defp decode(status, _body), do: {:error, {:http_status, status}}

  defp token do
    with app_id when is_binary(app_id) <- config(:app_id),
         path when is_binary(path) <- config(:key_file),
         {:ok, pem} <- File.read(path),
         {:ok, key} <- JWT.read_key(pem) do
      {:ok, JWT.sign(app_id, key)}
    else
      nil -> {:error, :not_configured}
      {:error, :invalid_key} -> {:error, :invalid_key}
      {:error, _file_error} -> {:error, :key_unreadable}
    end
  end

  defp base_url, do: config(:base_url) || @base_url
  defp config(key), do: Application.get_env(:abakus, __MODULE__, [])[key]
end

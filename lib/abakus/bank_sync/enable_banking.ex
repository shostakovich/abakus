defmodule Abakus.BankSync.EnableBanking do
  @moduledoc """
  Enable Banking's API (ADR 0020), as the application `ENABLE_BANKING_APP_ID` with the private key in the file
  `ENABLE_BANKING_KEY_FILE`; each request carries a fresh `Abakus.BankSync.JWT`. Personal accounts only.

  A fetch asked for while present carries the PSU headers (`Psu-Ip-Address`, `Psu-User-Agent`), so the bank does not
  count it against its four unattended fetches a day. A refusal for too many fetches is `:rate_limited`, one for a
  session that ended `:consent_ended`. Transactions come page by page; a continuation key that repeats is
  `:invalid_response`.
  """
  @behaviour Abakus.BankSync.Client

  alias Abakus.BankSync.JWT
  alias Abakus.HTTP

  @base_url "https://api.enablebanking.com"
  @timeout 30_000
  @ended_sessions ~w(EXPIRED_SESSION CLOSED_SESSION REVOKED_SESSION)

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

  @impl true
  def transactions(account_uid, date_from, psu),
    do: transaction_pages(account_uid, [date_from: Date.to_iso8601(date_from)], psu, [], [])

  defp transaction_pages(account_uid, params, psu, pages, keys) do
    case request(:get, account_path(account_uid, "transactions"),
           params: params,
           headers: psu_headers(psu)
         ) do
      {:ok, %{"transactions" => transactions} = page} when is_list(transactions) ->
        pages = [Enum.map(transactions, &transaction/1) | pages]

        case page["continuation_key"] do
          key when is_binary(key) and key != "" ->
            next_page(account_uid, params, psu, pages, [key | keys])

          _last ->
            {:ok, pages |> Enum.reverse() |> Enum.concat()}
        end

      {:ok, _other} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp next_page(account_uid, params, psu, pages, [key | seen] = keys) do
    if key in seen do
      {:error, :invalid_response}
    else
      params = Keyword.put(params, :continuation_key, key)
      transaction_pages(account_uid, params, psu, pages, keys)
    end
  end

  defp transaction(transaction) do
    %{
      status: transaction_status(transaction["status"]),
      entry_reference: text(transaction["entry_reference"]),
      transaction_id: text(transaction["transaction_id"]),
      date:
        Enum.find_value(
          ~w(booking_date value_date transaction_date),
          &date(transaction[&1])
        ),
      amount: signed_amount(transaction),
      creditor: text(get_in(transaction, [Access.key("creditor", %{}), "name"])),
      debtor: text(get_in(transaction, [Access.key("debtor", %{}), "name"])),
      remittance: remittance(transaction["remittance_information"])
    }
  end

  defp transaction_status("BOOK"), do: :booked
  defp transaction_status("PDNG"), do: :pending
  defp transaction_status(_other), do: :other

  defp signed_amount(transaction) do
    with %{"amount" => text} <- transaction["transaction_amount"],
         cents when is_integer(cents) <- cents(text) do
      case transaction["credit_debit_indicator"] do
        "DBIT" -> -abs(cents)
        "CRDT" -> abs(cents)
        _unknown -> cents
      end
    else
      _missing -> nil
    end
  end

  defp remittance(lines) when is_list(lines), do: for(line <- lines, text = text(line), do: text)
  defp remittance(_none), do: []

  @impl true
  def balances(account_uid, psu) do
    case request(:get, account_path(account_uid, "balances"), headers: psu_headers(psu)) do
      {:ok, %{"balances" => balances}} when is_list(balances) ->
        {:ok, for(raw <- balances, balance = balance(raw), do: balance)}

      {:ok, _other} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp balance(%{"balance_amount" => %{"amount" => text}} = balance) do
    if cents = cents(text) do
      %{
        type: balance_type(balance["balance_type"]),
        amount: cents,
        date: date(balance["reference_date"])
      }
    end
  end

  defp balance(_other), do: nil

  defp balance_type("CLBD"), do: :closing_booked
  defp balance_type("ITBD"), do: :interim_booked
  defp balance_type(_other), do: :other

  defp account_path(uid, resource),
    do: "/accounts/#{URI.encode(uid, &URI.char_unreserved?/1)}/#{resource}"

  defp psu_headers(nil), do: []

  defp psu_headers(%{ip_address: ip_address} = psu) do
    [{"psu-ip-address", ip_address}] ++
      if psu[:user_agent], do: [{"psu-user-agent", psu.user_agent}], else: []
  end

  # Whole cents with a decimal point, up to 12 digits of the currency; more decimals only as zeros.
  defp cents(text) when is_binary(text) do
    case Regex.run(~r/^([+-]?)(\d{1,12})(?:\.(\d{0,2})0*)?$/, String.trim(text),
           capture: :all_but_first
         ) do
      [sign, units | decimals] ->
        amount =
          String.to_integer(units) * 100 +
            (decimals |> Enum.join() |> String.pad_trailing(2, "0") |> String.to_integer())

        if sign == "-", do: -amount, else: amount

      nil ->
        nil
    end
  end

  defp cents(_not_text), do: nil

  defp date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp date(_missing), do: nil

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp text(_not_text), do: nil

  defp request(method, path, opts) do
    {headers, opts} = Keyword.pop(opts, :headers, [])

    with {:ok, token} <- token(),
         headers = [{"authorization", "Bearer " <> token} | headers],
         opts = [headers: headers, timeout: @timeout] ++ opts,
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

  defp decode(429, _body), do: {:error, :rate_limited}

  defp decode(status, body) do
    case JSON.decode(body) do
      {:ok, %{"error" => "ASPSP_RATE_LIMIT_EXCEEDED"}} -> {:error, :rate_limited}
      {:ok, %{"error" => error}} when error in @ended_sessions -> {:error, :consent_ended}
      _other -> {:error, {:http_status, status}}
    end
  end

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

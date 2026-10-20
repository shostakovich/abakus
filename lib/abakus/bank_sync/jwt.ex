defmodule Abakus.BankSync.JWT do
  @moduledoc """
  The token every request to Enable Banking carries: an RS256 JWT signed with the application's private key, its id
  as `kid`, valid for an hour (Enable Banking takes at most 24).
  """

  @lifetime_seconds 60 * 60

  @doc "A token for the application `app_id`, signed with its RSA private key, issued at `now`."
  def sign(app_id, private_key, now \\ DateTime.utc_now()) do
    issued_at = DateTime.to_unix(now)
    header = encode(%{typ: "JWT", alg: "RS256", kid: app_id})

    claims =
      encode(%{
        iss: "enablebanking.com",
        aud: "api.enablebanking.com",
        iat: issued_at,
        exp: issued_at + @lifetime_seconds
      })

    message = header <> "." <> claims

    message <>
      "." <> Base.url_encode64(:public_key.sign(message, :sha256, private_key), padding: false)
  end

  defp encode(map), do: map |> JSON.encode!() |> Base.url_encode64(padding: false)

  @doc "The RSA private key of a PEM file's content (PKCS #8 or PKCS #1)."
  def read_key(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _rest] -> decode_entry(entry)
      [] -> {:error, :invalid_key}
    end
  rescue
    _error -> {:error, :invalid_key}
  end

  defp decode_entry(entry) do
    case :public_key.pem_entry_decode(entry) do
      key when elem(key, 0) == :RSAPrivateKey -> {:ok, key}
      _other -> {:error, :invalid_key}
    end
  end
end

defmodule Abakus.WebAuthn do
  @moduledoc """
  Passkey ceremonies after W3C WebAuthn Level 3: registration (§7.1) and authentication (§7.2).

  Attestation is `none`. The browser hands over the public key as SPKI (`getPublicKey()`) and the
  authenticator data separately (`getAuthenticatorData()`), so no CBOR decoding is needed.
  Binary values travel as unpadded base64url.

  The SPKI is trusted as it comes and not matched against the COSE key in the authenticator
  data. That is acceptable: without attestation nothing the authenticator sends at registration
  is signed, so a dishonest client could make up both the authenticator data and its key anyway.
  The trust lies in the signed-in session (in sudo mode, over TLS, with CSRF protection) that
  adds the passkey, and every later sign-in proves possession of the stored key.
  """

  @es256 -7
  @eddsa -8
  @rs256 -257

  @p256 {1, 2, 840, 10_045, 3, 1, 7}
  @ed25519 {1, 3, 101, 112}

  @flag_up 0x01
  @flag_uv 0x04
  @flag_be 0x08
  @flag_bs 0x10
  @flag_at 0x40

  @max_credential_id_bytes 1023
  @min_rsa_bits 2048
  @timeout_ms 300_000

  @typedoc "`id` is the RP ID (a host), `origin` the exact origin the pages are served from."
  @type relying_party :: %{id: String.t(), origin: String.t(), name: String.t()}

  @type registered :: %{
          credential_id: binary,
          public_key: binary,
          algorithm: integer,
          sign_count: non_neg_integer,
          backup_eligible: boolean
        }

  def new_challenge, do: :crypto.strong_rand_bytes(32)

  def timeout_ms, do: @timeout_ms

  def encode(binary), do: Base.url_encode64(binary, padding: false)

  @doc "Options for `navigator.credentials.create()`."
  def registration_options(rp, challenge, %{handle: handle, name: name}, exclude_ids) do
    %{
      challenge: encode(challenge),
      rp: %{id: rp.id, name: rp.name},
      user: %{id: encode(handle), name: name, displayName: name},
      pubKeyCredParams: Enum.map([@eddsa, @es256, @rs256], &%{type: "public-key", alg: &1}),
      authenticatorSelection: %{
        residentKey: "required",
        requireResidentKey: true,
        userVerification: "required"
      },
      attestation: "none",
      excludeCredentials: Enum.map(exclude_ids, &%{type: "public-key", id: encode(&1)}),
      timeout: @timeout_ms
    }
  end

  @doc "Options for `navigator.credentials.get()`; discoverable credentials, so none are listed."
  def authentication_options(rp, challenge) do
    %{
      challenge: encode(challenge),
      rpId: rp.id,
      allowCredentials: [],
      userVerification: "required",
      timeout: @timeout_ms
    }
  end

  @doc """
  Verifies a new credential (§7.1). `response` holds `id`, `clientDataJSON`, `authenticatorData`,
  `publicKey` and `publicKeyAlgorithm` from the browser.
  """
  @spec verify_registration(map, binary, relying_party) :: {:ok, registered} | {:error, atom}
  def verify_registration(response, challenge, rp) do
    with {:ok, credential_id} <- decode(response, "id"),
         {:ok, client_data_json} <- decode(response, "clientDataJSON"),
         {:ok, auth_data} <- decode(response, "authenticatorData"),
         {:ok, public_key} <- decode(response, "publicKey"),
         {:ok, algorithm} <- fetch_integer(response, "publicKeyAlgorithm"),
         :ok <- verify_client_data(client_data_json, "webauthn.create", challenge, rp),
         {:ok, data} <- parse_authenticator_data(auth_data),
         :ok <- verify_authenticator_data(data, rp),
         :ok <- verify_attested_credential(data, credential_id),
         {:ok, _key} <- decode_public_key(public_key, algorithm) do
      {:ok,
       %{
         credential_id: credential_id,
         public_key: public_key,
         algorithm: algorithm,
         sign_count: data.sign_count,
         backup_eligible: flag?(data, @flag_be)
       }}
    end
  end

  @doc "The credential id of an assertion, to look up the stored passkey."
  def credential_id(response), do: decode(response, "id")

  @doc """
  Verifies an assertion (§7.2) against the stored passkey (`public_key`, `algorithm`,
  `sign_count`, `backup_eligible`) and the handle of its user. `response` holds `id`,
  `clientDataJSON`, `authenticatorData`, `signature` and `userHandle`. Returns the new sign count.
  """
  @spec verify_authentication(map, binary, relying_party, map, binary) ::
          {:ok, non_neg_integer} | {:error, atom}
  def verify_authentication(response, challenge, rp, passkey, user_handle) do
    with {:ok, client_data_json} <- decode(response, "clientDataJSON"),
         {:ok, auth_data} <- decode(response, "authenticatorData"),
         {:ok, signature} <- decode(response, "signature"),
         {:ok, handle} <- decode(response, "userHandle"),
         :ok <- check(Plug.Crypto.secure_compare(handle, user_handle), :user_handle),
         :ok <- verify_client_data(client_data_json, "webauthn.get", challenge, rp),
         {:ok, data} <- parse_authenticator_data(auth_data),
         :ok <- verify_authenticator_data(data, rp),
         :ok <- check(flag?(data, @flag_be) == passkey.backup_eligible, :backup_eligible),
         {:ok, key} <- decode_public_key(passkey.public_key, passkey.algorithm),
         signed = auth_data <> :crypto.hash(:sha256, client_data_json),
         :ok <- verify_signature(signed, signature, key, passkey.algorithm),
         :ok <- verify_sign_count(data.sign_count, passkey.sign_count) do
      {:ok, data.sign_count}
    end
  end

  defp decode(response, key) when is_map(response) do
    with value when is_binary(value) <- Map.get(response, key),
         {:ok, binary} <- Base.url_decode64(value, padding: false) do
      {:ok, binary}
    else
      _ -> {:error, :malformed}
    end
  end

  defp decode(_response, _key), do: {:error, :malformed}

  defp fetch_integer(response, key) do
    case Map.get(response, key) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, :malformed}
    end
  end

  # §7.1 steps 5–10, §7.2 steps 10–14.
  defp verify_client_data(json, type, challenge, rp) do
    with {:ok, %{} = client_data} <- decode_json(json),
         :ok <- check(client_data["type"] == type, :type),
         :ok <- check(challenge_matches?(client_data["challenge"], challenge), :challenge),
         :ok <- check(client_data["origin"] == rp.origin, :origin) do
      check(
        client_data["crossOrigin"] in [nil, false] and is_nil(client_data["topOrigin"]),
        :cross_origin
      )
    end
  end

  defp decode_json(json) do
    case JSON.decode(json) do
      {:ok, %{} = map} -> {:ok, map}
      _ -> {:error, :malformed}
    end
  end

  defp challenge_matches?(value, challenge) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, received} -> Plug.Crypto.secure_compare(received, challenge)
      :error -> false
    end
  end

  defp challenge_matches?(_value, _challenge), do: false

  defp parse_authenticator_data(<<rp_id_hash::binary-32, flags, sign_count::32, rest::binary>>) do
    {:ok, %{rp_id_hash: rp_id_hash, flags: flags, sign_count: sign_count, rest: rest}}
  end

  defp parse_authenticator_data(_auth_data), do: {:error, :malformed}

  # §7.1 steps 13–17, §7.2 steps 15–19.
  defp verify_authenticator_data(data, rp) do
    with :ok <- check(data.rp_id_hash == :crypto.hash(:sha256, rp.id), :rp_id),
         :ok <- check(flag?(data, @flag_up), :user_presence),
         :ok <- check(flag?(data, @flag_uv), :user_verification) do
      check(flag?(data, @flag_be) or not flag?(data, @flag_bs), :backup_state)
    end
  end

  defp verify_attested_credential(%{rest: rest} = data, credential_id) do
    with :ok <- check(flag?(data, @flag_at), :attested_credential),
         <<_aaguid::binary-16, length::16, id::binary-size(length), _key::binary>> <- rest,
         :ok <- check(length <= @max_credential_id_bytes, :credential_id) do
      check(id == credential_id, :credential_id)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed}
    end
  end

  defp flag?(%{flags: flags}, flag), do: Bitwise.band(flags, flag) != 0

  defp decode_public_key(spki, algorithm) do
    key = :public_key.pem_entry_decode({:SubjectPublicKeyInfo, spki, :not_encrypted})

    cond do
      not key_matches?(key, algorithm) -> {:error, :algorithm}
      weak?(key) -> {:error, :key_size}
      true -> {:ok, key}
    end
  rescue
    _ -> {:error, :public_key}
  end

  defp key_matches?({{:ECPoint, _}, {:namedCurve, @p256}}, @es256), do: true
  defp key_matches?({{:ECPoint, _}, {:namedCurve, @ed25519}}, @eddsa), do: true
  defp key_matches?({:RSAPublicKey, _, _}, @rs256), do: true
  defp key_matches?(_key, _algorithm), do: false

  defp weak?({:RSAPublicKey, modulus, _exponent}),
    do: modulus < Bitwise.bsl(1, @min_rsa_bits - 1)

  defp weak?(_key), do: false

  defp verify_signature(message, signature, key, algorithm) do
    digest = if algorithm == @eddsa, do: :none, else: :sha256
    check(:public_key.verify(message, digest, signature, key), :signature)
  rescue
    _ -> {:error, :signature}
  end

  # Synced passkeys report 0 throughout; any other count has to grow.
  defp verify_sign_count(0, 0), do: :ok
  defp verify_sign_count(new, stored) when new > stored, do: :ok
  defp verify_sign_count(_new, _stored), do: {:error, :sign_count}

  defp check(true, _reason), do: :ok
  defp check(_false, reason), do: {:error, reason}
end

defmodule Abakus.FakeAuthenticator do
  @moduledoc """
  A passkey authenticator played with `:crypto`, producing what the browser hands to the hooks.
  Every option breaks one part of a response.
  """

  import Bitwise

  @algorithms %{es256: -7, eddsa: -8, rs256: -257}

  @flag_up 0x01
  @flag_uv 0x04
  @flag_at 0x40

  @doc "Options: `:rsa_bits` (2048) and `:credential_id` (16 random bytes)."
  def new(kind \\ :es256, opts \\ []) do
    private = generate(kind, Keyword.get(opts, :rsa_bits, 2048))

    %{
      kind: kind,
      algorithm: Map.fetch!(@algorithms, kind),
      private: private,
      spki: spki(private),
      credential_id:
        Keyword.get_lazy(opts, :credential_id, fn -> :crypto.strong_rand_bytes(16) end),
      sign_count: 0
    }
  end

  def relying_party,
    do: %{id: "localhost", origin: "http://localhost:4002", name: "Abakus"}

  @doc "The browser's answer to `navigator.credentials.create()`."
  def registration(authenticator, challenge, opts \\ []) do
    rp = Keyword.get(opts, :rp, relying_party())
    client_data = client_data("webauthn.create", challenge, rp, opts)
    flags = Keyword.get(opts, :flags, @flag_up ||| @flag_uv ||| @flag_at)
    attested_id = Keyword.get(opts, :attested_id, authenticator.credential_id)

    attested =
      <<0::128, byte_size(attested_id)::16, attested_id::binary, "cose key, unused">>

    %{
      "id" => encode(authenticator.credential_id),
      "clientDataJSON" => encode(client_data),
      "authenticatorData" =>
        encode(authenticator_data(rp, flags, authenticator.sign_count, opts) <> attested),
      "publicKey" => encode(Keyword.get(opts, :spki, authenticator.spki)),
      "publicKeyAlgorithm" => Keyword.get(opts, :algorithm, authenticator.algorithm)
    }
  end

  @doc "The browser's answer to `navigator.credentials.get()`, signed with the private key."
  def assertion(authenticator, challenge, user_handle, opts \\ []) do
    rp = Keyword.get(opts, :rp, relying_party())
    client_data = client_data("webauthn.get", challenge, rp, opts)
    flags = Keyword.get(opts, :flags, @flag_up ||| @flag_uv)
    sign_count = Keyword.get(opts, :sign_count, authenticator.sign_count)
    auth_data = authenticator_data(rp, flags, sign_count, opts)

    signed =
      auth_data <> :crypto.hash(:sha256, Keyword.get(opts, :signed_client_data, client_data))

    signer = Keyword.get(opts, :signer, authenticator)

    %{
      "id" => encode(authenticator.credential_id),
      "clientDataJSON" => encode(client_data),
      "authenticatorData" => encode(auth_data),
      "signature" => encode(sign(signer, signed)),
      "userHandle" => encode(user_handle)
    }
  end

  def encode(binary), do: Base.url_encode64(binary, padding: false)

  defp client_data(type, challenge, rp, opts) do
    %{
      "type" => Keyword.get(opts, :type, type),
      "challenge" => encode(Keyword.get(opts, :challenge, challenge)),
      "origin" => Keyword.get(opts, :origin, rp.origin),
      "crossOrigin" => Keyword.get(opts, :cross_origin, false)
    }
    |> Map.merge(Keyword.get(opts, :client_data, %{}))
    |> JSON.encode!()
  end

  defp authenticator_data(rp, flags, sign_count, opts) do
    rp_id = Keyword.get(opts, :rp_id, rp.id)
    <<:crypto.hash(:sha256, rp_id)::binary, flags, sign_count::32>>
  end

  defp generate(:es256, _bits), do: :public_key.generate_key({:namedCurve, :secp256r1})
  defp generate(:eddsa, _bits), do: :public_key.generate_key({:namedCurve, :ed25519})
  defp generate(:rs256, bits), do: :public_key.generate_key({:rsa, bits, 65_537})

  defp spki({:ECPrivateKey, _, _, curve, point, _}), do: encode_spki({{:ECPoint, point}, curve})

  defp spki({:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _}),
    do: encode_spki({:RSAPublicKey, n, e})

  defp encode_spki(public_key) do
    {:SubjectPublicKeyInfo, der, :not_encrypted} =
      :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)

    der
  end

  defp sign(%{kind: :eddsa, private: private}, message),
    do: :public_key.sign(message, :none, private)

  defp sign(%{private: private}, message), do: :public_key.sign(message, :sha256, private)
end

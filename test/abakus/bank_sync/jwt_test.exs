defmodule Abakus.BankSync.JWTTest do
  use ExUnit.Case, async: true

  alias Abakus.BankSync.JWT

  @now ~U[2026-10-20 08:00:00Z]

  setup_all do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    {:RSAPrivateKey, _version, modulus, exponent, _d, _p, _q, _e1, _e2, _c, _other} = key

    %{key: key, public_key: {:RSAPublicKey, modulus, exponent}}
  end

  defp decode(part), do: part |> Base.url_decode64!(padding: false) |> JSON.decode!()

  test "verifies with the public key and carries the expected claims", %{
    key: key,
    public_key: public_key
  } do
    token = JWT.sign("app-123", key, @now)
    [header, claims, signature] = String.split(token, ".")

    assert :public_key.verify(
             header <> "." <> claims,
             :sha256,
             Base.url_decode64!(signature, padding: false),
             public_key
           )

    assert decode(header) == %{"typ" => "JWT", "alg" => "RS256", "kid" => "app-123"}

    assert %{
             "iss" => "enablebanking.com",
             "aud" => "api.enablebanking.com",
             "iat" => iat,
             "exp" => exp
           } = decode(claims)

    assert iat == DateTime.to_unix(@now)
    assert (exp - iat) in 1..(24 * 60 * 60)
  end

  test "a changed token does not verify", %{key: key, public_key: public_key} do
    [header, _claims, signature] = String.split(JWT.sign("app-123", key, @now), ".")
    forged = Base.url_encode64(~s|{"iss":"enablebanking.com"}|, padding: false)

    refute :public_key.verify(
             header <> "." <> forged,
             :sha256,
             Base.url_decode64!(signature, padding: false),
             public_key
           )
  end

  describe "read_key/1" do
    test "reads a PKCS #8 and a PKCS #1 PEM", %{key: key} do
      pkcs8 = :public_key.pem_encode([:public_key.pem_entry_encode(:PrivateKeyInfo, key)])
      pkcs1 = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])

      assert JWT.read_key(pkcs8) == {:ok, key}
      assert JWT.read_key(pkcs1) == {:ok, key}
    end

    test "refuses what is no RSA private key" do
      assert JWT.read_key("not a key") == {:error, :invalid_key}
      assert JWT.read_key("") == {:error, :invalid_key}
    end
  end
end

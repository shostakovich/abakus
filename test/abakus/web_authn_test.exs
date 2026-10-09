defmodule Abakus.WebAuthnTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Abakus.FakeAuthenticator, as: Fake
  alias Abakus.WebAuthn

  @flag_up 0x01
  @flag_uv 0x04
  @flag_be 0x08
  @flag_bs 0x10
  @flag_at 0x40

  setup do
    %{
      rp: Fake.relying_party(),
      challenge: WebAuthn.new_challenge(),
      handle: :crypto.strong_rand_bytes(16)
    }
  end

  describe "options" do
    test "registration asks for a discoverable, user-verified passkey without attestation", %{
      rp: rp,
      challenge: challenge,
      handle: handle
    } do
      options =
        WebAuthn.registration_options(rp, challenge, %{handle: handle, name: "a@b.de"}, ["id"])

      assert options.challenge == Fake.encode(challenge)
      assert options.rp == %{id: "localhost", name: "Abakus"}
      assert options.user.id == Fake.encode(handle)
      assert Enum.map(options.pubKeyCredParams, & &1.alg) == [-8, -7, -257]
      assert options.authenticatorSelection.residentKey == "required"
      assert options.authenticatorSelection.userVerification == "required"
      assert options.attestation == "none"
      assert options.excludeCredentials == [%{type: "public-key", id: Fake.encode("id")}]
    end

    test "authentication lists no credentials and requires user verification", %{
      rp: rp,
      challenge: challenge
    } do
      options = WebAuthn.authentication_options(rp, challenge)

      assert options.allowCredentials == []
      assert options.rpId == "localhost"
      assert options.userVerification == "required"
    end
  end

  describe "verify_registration/3" do
    for kind <- [:es256, :eddsa, :rs256] do
      test "accepts a #{kind} passkey", %{rp: rp, challenge: challenge} do
        authenticator = Fake.new(unquote(kind))

        assert {:ok, credential} =
                 WebAuthn.verify_registration(
                   Fake.registration(authenticator, challenge),
                   challenge,
                   rp
                 )

        assert credential == %{
                 credential_id: authenticator.credential_id,
                 public_key: authenticator.spki,
                 algorithm: authenticator.algorithm,
                 sign_count: 0,
                 backup_eligible: false
               }
      end
    end

    test "rejects a broken response", %{rp: rp, challenge: challenge} do
      authenticator = Fake.new()
      other = Fake.new(:eddsa)
      flags = @flag_up ||| @flag_uv ||| @flag_at

      cases = [
        type: [type: "webauthn.get"],
        challenge: [challenge: WebAuthn.new_challenge()],
        origin: [origin: "https://evil.example"],
        cross_origin: [cross_origin: true],
        cross_origin: [client_data: %{"topOrigin" => "https://evil.example"}],
        rp_id: [rp_id: "evil.example"],
        user_presence: [flags: bxor(flags, @flag_up)],
        user_verification: [flags: bxor(flags, @flag_uv)],
        backup_state: [flags: flags ||| @flag_bs],
        attested_credential: [flags: bxor(flags, @flag_at)],
        credential_id: [attested_id: :crypto.strong_rand_bytes(16)],
        credential_id: [attested_id: :binary.copy("x", 1024)],
        algorithm: [algorithm: -8],
        algorithm: [algorithm: -999],
        algorithm: [spki: other.spki],
        public_key: [spki: "not a key"]
      ]

      for {reason, opts} <- cases do
        response = Fake.registration(authenticator, challenge, opts)

        assert WebAuthn.verify_registration(response, challenge, rp) == {:error, reason},
               "expected #{reason} for #{inspect(opts)}"
      end
    end

    test "accepts a backed-up passkey and records that it may be backed up", %{
      rp: rp,
      challenge: challenge
    } do
      flags = @flag_up ||| @flag_uv ||| @flag_at ||| @flag_be ||| @flag_bs
      response = Fake.registration(Fake.new(), challenge, flags: flags)

      assert {:ok, %{backup_eligible: true}} =
               WebAuthn.verify_registration(response, challenge, rp)
    end

    test "rejects a credential id that is too long, even when both ids match", %{
      rp: rp,
      challenge: challenge
    } do
      authenticator = Fake.new(:es256, credential_id: :binary.copy("x", 1024))
      response = Fake.registration(authenticator, challenge)

      assert WebAuthn.verify_registration(response, challenge, rp) == {:error, :credential_id}

      authenticator = Fake.new(:es256, credential_id: :binary.copy("x", 1023))
      response = Fake.registration(authenticator, challenge)

      assert {:ok, _credential} = WebAuthn.verify_registration(response, challenge, rp)
    end

    test "rejects an RSA key shorter than 2048 bits", %{rp: rp, challenge: challenge} do
      response = Fake.registration(Fake.new(:rs256, rsa_bits: 1024), challenge)

      assert WebAuthn.verify_registration(response, challenge, rp) == {:error, :key_size}
    end

    test "rejects missing and malformed fields", %{rp: rp, challenge: challenge} do
      response = Fake.registration(Fake.new(), challenge)

      for broken <- [
            Map.delete(response, "clientDataJSON"),
            Map.put(response, "authenticatorData", "!!"),
            Map.put(response, "authenticatorData", Fake.encode("short")),
            Map.put(response, "clientDataJSON", Fake.encode("not json")),
            Map.put(response, "publicKeyAlgorithm", "-7")
          ] do
        assert WebAuthn.verify_registration(broken, challenge, rp) == {:error, :malformed}
      end
    end
  end

  describe "verify_authentication/5" do
    for kind <- [:es256, :eddsa, :rs256] do
      test "accepts a #{kind} assertion", %{rp: rp, challenge: challenge, handle: handle} do
        authenticator = Fake.new(unquote(kind))
        response = Fake.assertion(authenticator, challenge, handle)

        assert WebAuthn.verify_authentication(
                 response,
                 challenge,
                 rp,
                 passkey(authenticator),
                 handle
               ) ==
                 {:ok, 0}
      end
    end

    test "rejects a broken assertion", %{rp: rp, challenge: challenge, handle: handle} do
      authenticator = Fake.new()
      flags = @flag_up ||| @flag_uv

      cases = [
        type: [type: "webauthn.create"],
        challenge: [challenge: WebAuthn.new_challenge()],
        origin: [origin: "http://localhost:4000"],
        cross_origin: [cross_origin: true],
        cross_origin: [client_data: %{"topOrigin" => "https://evil.example"}],
        rp_id: [rp_id: "evil.example"],
        user_presence: [flags: bxor(flags, @flag_up)],
        user_verification: [flags: bxor(flags, @flag_uv)],
        backup_state: [flags: flags ||| @flag_bs],
        backup_eligible: [flags: flags ||| @flag_be],
        signature: [signer: Fake.new()],
        signature: [signed_client_data: "tampered"]
      ]

      for {reason, opts} <- cases do
        response = Fake.assertion(authenticator, challenge, handle, opts)

        assert WebAuthn.verify_authentication(
                 response,
                 challenge,
                 rp,
                 passkey(authenticator),
                 handle
               ) ==
                 {:error, reason},
               "expected #{reason} for #{inspect(opts)}"
      end
    end

    test "rejects an assertion without user handle or signature", %{
      rp: rp,
      challenge: challenge,
      handle: handle
    } do
      authenticator = Fake.new()
      response = Fake.assertion(authenticator, challenge, handle)

      for {broken, reason} <- [
            {Map.delete(response, "userHandle"), :malformed},
            {Map.put(response, "userHandle", ""), :user_handle},
            {Map.delete(response, "signature"), :malformed},
            {Map.put(response, "signature", ""), :signature}
          ] do
        assert WebAuthn.verify_authentication(
                 broken,
                 challenge,
                 rp,
                 passkey(authenticator),
                 handle
               ) == {:error, reason}
      end
    end

    test "requires the backup eligibility recorded at registration", %{
      rp: rp,
      challenge: challenge,
      handle: handle
    } do
      authenticator = Fake.new()
      eligible = %{passkey(authenticator) | backup_eligible: true}

      for {flags, expected} <- [
            {@flag_up ||| @flag_uv, {:error, :backup_eligible}},
            {@flag_up ||| @flag_uv ||| @flag_be, {:ok, 0}},
            {@flag_up ||| @flag_uv ||| @flag_be ||| @flag_bs, {:ok, 0}}
          ] do
        response = Fake.assertion(authenticator, challenge, handle, flags: flags)

        assert WebAuthn.verify_authentication(response, challenge, rp, eligible, handle) ==
                 expected
      end
    end

    test "rejects the passkey of another user", %{rp: rp, challenge: challenge, handle: handle} do
      authenticator = Fake.new()
      response = Fake.assertion(authenticator, challenge, :crypto.strong_rand_bytes(16))

      assert WebAuthn.verify_authentication(
               response,
               challenge,
               rp,
               passkey(authenticator),
               handle
             ) ==
               {:error, :user_handle}
    end

    test "rejects a signature over a different key's algorithm", %{
      rp: rp,
      challenge: challenge,
      handle: handle
    } do
      authenticator = Fake.new()
      response = Fake.assertion(authenticator, challenge, handle)
      stored = %{passkey(authenticator) | algorithm: -257}

      assert WebAuthn.verify_authentication(response, challenge, rp, stored, handle) ==
               {:error, :algorithm}
    end

    test "tolerates a count of zero and rejects one that does not grow", %{
      rp: rp,
      challenge: challenge,
      handle: handle
    } do
      authenticator = Fake.new()

      for {stored, sent, expected} <- [
            {0, 0, {:ok, 0}},
            {0, 1, {:ok, 1}},
            {5, 6, {:ok, 6}},
            {5, 5, {:error, :sign_count}},
            {5, 4, {:error, :sign_count}},
            {5, 0, {:error, :sign_count}}
          ] do
        response = Fake.assertion(authenticator, challenge, handle, sign_count: sent)
        stored_passkey = %{passkey(authenticator) | sign_count: stored}

        assert WebAuthn.verify_authentication(response, challenge, rp, stored_passkey, handle) ==
                 expected
      end
    end
  end

  defp passkey(authenticator) do
    %{
      public_key: authenticator.spki,
      algorithm: authenticator.algorithm,
      sign_count: 0,
      backup_eligible: false
    }
  end
end

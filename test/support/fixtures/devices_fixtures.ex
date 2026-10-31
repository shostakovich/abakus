defmodule Abakus.DevicesFixtures do
  @moduledoc "Apps signed in for tests, as `Abakus.Devices` signs them in."

  alias Abakus.Devices

  def verifier, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  def challenge(verifier), do: Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

  def client, do: Devices.client("abakus-apple")

  @doc "Signs in the device `name` for the budget owner's scope; its tokens and `device_id`."
  def sign_in_device(scope, name \\ "MacBook") do
    verifier = verifier()
    {:ok, code} = Devices.authorize(scope, client(), name, challenge(verifier))
    {:ok, tokens} = Devices.exchange_code(client().id, code, verifier)
    tokens
  end
end

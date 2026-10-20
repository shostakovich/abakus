defmodule Abakus.BankSync.Client do
  @moduledoc """
  The bank sync's provider, Enable Banking (ADR 0020): the banks of a country, the start of a consent at one of them
  and the session its code opens, with the bank's accounts. Read only.
  """

  @typedoc "A bank (ASPSP) with how long, in seconds, a consent at it may last at most."
  @type bank :: %{
          name: String.t(),
          country: String.t(),
          maximum_consent_validity: pos_integer() | nil
        }

  @type auth_request :: %{
          bank: %{name: String.t(), country: String.t()},
          valid_until: DateTime.t(),
          redirect_url: String.t(),
          state: String.t()
        }

  @typedoc "One of the bank's accounts in a session: the provider's id, with its name and IBAN if the bank has them."
  @type account :: %{uid: String.t(), name: String.t() | nil, iban: String.t() | nil}

  @typedoc "An opened session, with when its consent ends if the provider says so."
  @type session :: %{
          session_id: String.t(),
          valid_until: DateTime.t() | nil,
          accounts: [account]
        }

  @doc "Whether the provider is configured: the application id and its private key."
  @callback available?() :: boolean

  @doc "The banks of a country (ISO 3166 alpha-2) that personal accounts can connect to."
  @callback banks(country :: String.t()) :: {:ok, [bank]} | {:error, term}

  @doc "Starts a consent at the bank; the URL leads the user there, the bank sends them back with a code."
  @callback start_auth(auth_request) :: {:ok, url :: String.t()} | {:error, term}

  @doc "Opens the session of the code the bank sent the user back with."
  @callback create_session(code :: String.t()) :: {:ok, session} | {:error, term}
end

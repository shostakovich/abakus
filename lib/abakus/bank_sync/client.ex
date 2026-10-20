defmodule Abakus.BankSync.Client do
  @moduledoc """
  The bank sync's provider, Enable Banking (ADR 0020): the banks of a country, the start of a consent at one of them
  and the session its code opens, with the bank's accounts, and their transactions and balances. Read only.
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

  @typedoc """
  Who asks for a fetch while present ("Jetzt abrufen"): their IP address and user agent, so the bank does not count
  it against its unattended fetches; nil for a scheduled fetch.
  """
  @type psu :: %{ip_address: String.t(), user_agent: String.t() | nil} | nil

  @typedoc """
  A transaction as the bank reports it: booked, pending or anything else, with the bank's ids, its date (booking,
  else value, else transaction date) and amount in cents (negative for a debit) if it has them, the creditor's and
  debtor's names and the remittance lines.
  """
  @type transaction :: %{
          status: :booked | :pending | :other,
          entry_reference: String.t() | nil,
          transaction_id: String.t() | nil,
          date: Date.t() | nil,
          amount: integer | nil,
          creditor: String.t() | nil,
          debtor: String.t() | nil,
          remittance: [String.t()]
        }

  @typedoc "A balance of the account in cents: closing booked, interim booked or another kind, with its reference date."
  @type balance :: %{
          type: :closing_booked | :interim_booked | :other,
          amount: integer,
          date: Date.t() | nil
        }

  @doc "Whether the provider is configured: the application id and its private key."
  @callback available?() :: boolean

  @doc "The banks of a country (ISO 3166 alpha-2) that personal accounts can connect to."
  @callback banks(country :: String.t()) :: {:ok, [bank]} | {:error, term}

  @doc "Starts a consent at the bank; the URL leads the user there, the bank sends them back with a code."
  @callback start_auth(auth_request) :: {:ok, url :: String.t()} | {:error, term}

  @doc "Opens the session of the code the bank sent the user back with."
  @callback create_session(code :: String.t()) :: {:ok, session} | {:error, term}

  @doc "The transactions of the bank's account (its `uid`) from a date on, all pages of them."
  @callback transactions(account_uid :: String.t(), date_from :: Date.t(), psu) ::
              {:ok, [transaction]} | {:error, term}

  @doc "The balances of the bank's account (its `uid`)."
  @callback balances(account_uid :: String.t(), psu) :: {:ok, [balance]} | {:error, term}
end

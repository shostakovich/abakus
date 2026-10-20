defmodule Abakus.BankSync do
  @moduledoc """
  Bank sync through Enable Banking (ADR 0020), the budget owner's alone: every function takes `%Scope{}` (ADR 0019)
  and raises `Abakus.BankSync.AccessError` for anyone else.

  Connecting a bank: `authorize/3` starts a consent at the chosen bank for as long as the bank allows, with a random
  state the caller keeps (in the session) for the bank's way back; `connect/3` opens the session of the code it
  brings and keeps the bank connection with the bank's accounts, unlinked until `assign_accounts/3` gives each an
  account that takes entries, with the date to fetch from. The client is a behaviour (`Abakus.BankSync.Client`),
  configured as `:client`.
  """

  import Ecto.Query
  import Abakus.Owned

  alias Abakus.BankSync.{AccessError, Connection, LinkedAccount}
  alias Abakus.{Import, Ledger, LocalTime, Repo}
  alias Abakus.Ledger.Account
  alias Abakus.Users.Scope

  @default_consent_seconds 90 * 24 * 60 * 60

  @doc "Whether bank sync is set up: the provider has its application id and private key."
  def available?, do: client().available?()

  @doc "The banks of a country (ISO 3166 alpha-2) by name."
  def banks(%Scope{} = scope, country) do
    owner!(scope)

    with {:ok, banks} <- client().banks(country),
         do: {:ok, Enum.sort_by(banks, &String.downcase(&1.name))}
  end

  @doc """
  Starts a consent at the bank `%{name, country}` until the longest it allows and returns the URL to send the user
  to, with what `connect/3` needs once they are back: `%{state, bank_name, bank_country, valid_until}`. The bank
  sends them to `redirect_url` with the state and a code.
  """
  def authorize(%Scope{} = scope, %{name: name, country: country}, redirect_url) do
    with {:ok, banks} <- banks(scope, country),
         {:ok, bank} <- find_bank(banks, name),
         auth = auth(bank),
         {:ok, url} <-
           client().start_auth(%{
             bank: %{name: bank.name, country: bank.country},
             valid_until: auth.valid_until,
             redirect_url: redirect_url,
             state: auth.state
           }) do
      {:ok, %{url: url, auth: auth}}
    end
  end

  defp find_bank(banks, name) do
    case Enum.find(banks, &(&1.name == name)) do
      nil -> {:error, :unknown_bank}
      bank -> {:ok, bank}
    end
  end

  defp auth(bank) do
    seconds = bank.maximum_consent_validity || @default_consent_seconds

    %{
      state: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false),
      bank_name: bank.name,
      bank_country: bank.country,
      valid_until: LocalTime.utc_now() |> DateTime.add(seconds) |> DateTime.truncate(:second)
    }
  end

  @doc """
  Opens the session of the code the bank sent the user back with, for the consent `auth` of `authorize/3`, and keeps
  it as a bank connection with the bank's accounts, all unlinked.
  """
  def connect(%Scope{} = scope, auth, code) do
    owner!(scope)

    with {:ok, session} <- client().create_session(code) do
      connection =
        Repo.insert!(%Connection{
          user_id: user_id(scope),
          provider: :enable_banking,
          bank_name: auth.bank_name,
          bank_country: auth.bank_country,
          session_id: session.session_id,
          valid_until: Abakus.Schema.usec(session.valid_until || auth.valid_until),
          linked_accounts: Enum.map(session.accounts, &linked_account/1)
        })

      {:ok, preload(connection)}
    end
  end

  defp linked_account(account),
    do: %LinkedAccount{provider_account_id: account.uid, name: account.name, iban: account.iban}

  @doc "The bank connections, oldest first, with their accounts and the accounts these feed."
  def list_connections(%Scope{} = scope) do
    owner!(scope)

    from(c in owned(Connection, scope), order_by: c.id)
    |> Repo.all()
    |> preload()
  end

  def get_connection!(%Scope{} = scope, id) do
    owner!(scope)
    Connection |> owned(scope) |> Repo.get!(id) |> preload()
  end

  defp preload(connection), do: Repo.preload(connection, [linked_accounts: :account], force: true)

  @doc "Removes the bank connection, unless it is gone already; what it imported stays."
  def delete_connection(%Scope{} = scope, %Connection{} = connection) do
    owner!(scope)
    Repo.delete(own!(scope, connection), allow_stale: true)
  end

  @doc "The accounts a bank account can feed, `Abakus.Import.accounts/1`."
  def accounts(%Scope{} = scope), do: Import.accounts(owner!(scope))

  @doc """
  The date the first fetch into the account starts at, unless chosen otherwise: the day after its newest reconciled
  transaction, which nothing imported may predate anyway, else today.
  """
  def start_date(%Scope{} = scope, %Account{} = account) do
    case Ledger.last_reconciled_date(owner!(scope), account) do
      nil -> LocalTime.today()
      date -> Date.add(date, 1)
    end
  end

  @doc """
  Assigns the connection's accounts, `%{linked_account_id => %{account_id, start_date}}`, all or none; a nil
  account leaves one unlinked. Refuses an account that `accounts/1` does not offer, unless the bank account keeps
  it, or that another bank account feeds already, and a linked one without a start date, with a message.
  """
  def assign_accounts(%Scope{} = scope, %Connection{} = connection, assignments) do
    connection = get_connection!(scope, connection.id)
    offered = Map.new(accounts(scope), &{&1.id, &1})

    linked = Enum.filter(connection.linked_accounts, &Map.has_key?(assignments, &1.id))

    Repo.transact(fn ->
      # Cleared first, so that two bank accounts can swap their accounts.
      Repo.update_all(
        from(l in LinkedAccount, where: l.id in ^Enum.map(linked, & &1.id)),
        set: [account_id: nil]
      )

      with {:ok, _linked} <-
             Import.collect(linked, &assign(&1, assignments[&1.id], offered)),
           do: {:ok, get_connection!(scope, connection.id)}
    end)
  end

  defp assign(linked, attrs, offered) do
    account_id = attrs[:account_id]

    if account_id && account_id != linked.account_id && !Map.has_key?(offered, account_id) do
      {:error, "Das gewählte Konto nimmt keine Bankumsätze."}
    else
      linked
      |> LinkedAccount.assign_changeset(attrs)
      |> rewrite_account()
      |> Repo.update()
      |> assigned(linked, offered)
    end
  end

  # Written even when unchanged, as the transaction cleared it first.
  defp rewrite_account(changeset),
    do:
      Ecto.Changeset.force_change(
        changeset,
        :account_id,
        Ecto.Changeset.get_field(changeset, :account_id)
      )

  defp assigned({:ok, linked}, _before, _offered), do: {:ok, linked}

  defp assigned({:error, changeset}, linked, offered) do
    cond do
      changeset.errors[:start_date] ->
        {:error, "#{label(linked)} braucht ein Datum, ab dem Abakus abruft."}

      changeset.errors[:account_id] ->
        account = offered[Ecto.Changeset.get_field(changeset, :account_id)]
        {:error, "#{account.name} bekommt schon die Umsätze eines anderen Bankkontos."}
    end
  end

  defp label(%LinkedAccount{name: name, iban: iban}), do: name || iban || "Ein Bankkonto"

  @doc "A sentence for why a request to the bank failed."
  def error_message(:not_configured), do: "Bank-Sync ist nicht eingerichtet."
  def error_message(:unknown_bank), do: "Diese Bank bietet Enable Banking nicht an."
  def error_message(:invalid_key), do: "Der private Schlüssel für Enable Banking ist ungültig."

  def error_message(:key_unreadable),
    do: "Die Datei mit dem privaten Schlüssel für Enable Banking lässt sich nicht lesen."

  def error_message(:timeout), do: "Enable Banking hat nicht rechtzeitig geantwortet."
  def error_message(:unreachable), do: "Enable Banking ist nicht erreichbar."
  def error_message(:too_large), do: "Die Antwort von Enable Banking ist zu groß."
  def error_message(:invalid_response), do: "Enable Banking hat unerwartet geantwortet."

  def error_message({:http_status, status}),
    do: "Enable Banking hat die Anfrage abgelehnt (HTTP #{status})."

  def error_message(message) when is_binary(message), do: message

  defp owner!(scope) do
    if Scope.budget_owner?(scope), do: scope, else: raise(AccessError)
  end

  defp client, do: Application.fetch_env!(:abakus, __MODULE__)[:client]
end

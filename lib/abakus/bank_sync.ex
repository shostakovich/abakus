defmodule Abakus.BankSync do
  @moduledoc """
  Bank sync through Enable Banking (ADR 0020), the budget owner's alone: every function that takes `%Scope{}` (ADR
  0019) raises `Abakus.BankSync.AccessError` for anyone else, except `failing?/1`, which takes the system's alone.

  Connecting a bank: `authorize/3` starts a consent at the chosen bank for as long as the bank allows, with a random
  state the caller keeps (in the session) for the bank's way back; `connect/3` opens the session of the code it
  brings and keeps the bank connection with the bank's accounts, unlinked until `assign_accounts/3` gives each an
  account that takes entries, with the date to fetch from. `renew/3` runs the same way for an existing connection,
  which keeps its linked accounts. The client is a behaviour (`Abakus.BankSync.Client`), configured as `:client`.

  Fetching (`fetch/3`, on schedule `fetch_all/1`): each linked account from its start date on the first time, later
  from 14 days before its last successful fetch, nothing dated before its start date, one failing account keeping none of the others from it; at most one
  fetch per connection at a time, each kept as a sync run once it is done (an unexpected failure as its error).
  Booked and pending transactions come in through the import core (`Abakus.Import`) from source `bank` with the
  owner's scope, and the bank's balance becomes the account's bank balance. Pending ones clean up after themselves
  (ADR 0021): one dated in the fetched window and after the newest reconciled transaction that the bank no longer
  reports as pending is removed while it is unapproved; an approved one stays, and its booked version is proposed as
  its match. A connection whose consent has ended is not fetched until it is renewed; one the bank says has ended
  ends then.

  From 14 days before a consent ends until it is renewed, `expiring_consents/1` lists its connection for the banner in
  Finanzen.
  """

  import Ecto.Query
  import Abakus.Owned

  require Logger

  alias Abakus.BankSync.{AccessError, Connection, LinkedAccount, SyncRun}
  alias Abakus.{Format, Import, Ledger, LocalTime, Money, Names, Repo}
  alias Abakus.Ledger.{Account, TransactionOrigin}
  alias Abakus.Users.Scope

  @default_consent_seconds 90 * 24 * 60 * 60
  @refetch_days 14
  @recent_runs 5
  @expiring_days 14
  @sepa_prefixes ~r/(?<=^|\s)(?:EREF|KREF|MREF|CRED|DEBT|SVWZ|ABWA|ABWE|IBAN|BIC|COAM|OAMT|SQTP|PURP)\+/

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

  @doc """
  Starts a new consent at the connection's bank, as `authorize/3` does; `connect/3` then renews the connection with
  it, as the auth carries the connection's id.
  """
  def renew(%Scope{} = scope, %Connection{} = connection, redirect_url) do
    connection = own!(owner!(scope), connection)
    bank = %{name: connection.bank_name, country: connection.bank_country}

    with {:ok, started} <- authorize(scope, bank, redirect_url),
         do: {:ok, put_in(started.auth[:connection_id], connection.id)}
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
  it as a bank connection with the bank's accounts, all unlinked. With the `auth` of `renew/3` it renews that
  connection instead: the new session and consent, its error gone and its linked accounts kept,
  each found by the bank's id, else by its IBAN; the session's other accounts come unlinked, and linked accounts it
  no longer has go.
  """
  def connect(%Scope{} = scope, auth, code) do
    owner!(scope)

    with {:ok, session} <- client().create_session(code) do
      case auth do
        %{connection_id: id} -> renew_connection(scope, id, auth, session)
        _new -> {:ok, insert_connection(scope, auth, session)}
      end
    end
  end

  defp insert_connection(scope, auth, session) do
    Repo.insert!(%Connection{
      user_id: user_id(scope),
      provider: :enable_banking,
      bank_name: auth.bank_name,
      bank_country: auth.bank_country,
      session_id: session.session_id,
      valid_until: valid_until(auth, session),
      linked_accounts: Enum.map(session.accounts, &linked_account/1)
    })
    |> preload()
  end

  defp renew_connection(scope, id, auth, session) do
    Repo.transact(fn ->
      case Repo.get(owned(Connection, scope), id) do
        nil ->
          {:error, :unknown_connection}

        connection ->
          connection = Repo.preload(connection, :linked_accounts)
          renew_accounts(connection, session.accounts)

          connection
          |> Ecto.Changeset.change(
            session_id: session.session_id,
            valid_until: valid_until(auth, session),
            last_error: nil
          )
          |> Repo.update!()

          {:ok, get_connection!(scope, id)}
      end
    end)
  end

  defp valid_until(auth, session), do: Abakus.Schema.usec(session.valid_until || auth.valid_until)

  # The provider's account ids may change with a new session, so an account is also recognised by its IBAN.
  defp renew_accounts(connection, accounts) do
    {by_uid, linked_left, accounts_left} =
      pair_accounts(connection.linked_accounts, accounts, &(&1.provider_account_id == &2.uid))

    {by_iban, gone, new} =
      pair_accounts(linked_left, accounts_left, &(&1.iban != nil and &1.iban == &2.iban))

    Enum.each(gone, &Repo.delete!/1)

    for {linked, account} <- by_uid ++ by_iban do
      linked
      |> Ecto.Changeset.change(
        provider_account_id: account.uid,
        name: account.name,
        iban: account.iban
      )
      |> Repo.update!()
    end

    for account <- new,
        do: Repo.insert!(%{linked_account(account) | connection_id: connection.id})
  end

  defp pair_accounts(linked_accounts, accounts, same?) do
    Enum.reduce(linked_accounts, {[], [], accounts}, fn linked, {pairs, unpaired, left} ->
      case Enum.find(left, &same?.(linked, &1)) do
        nil -> {pairs, [linked | unpaired], left}
        account -> {[{linked, account} | pairs], unpaired, List.delete(left, account)}
      end
    end)
  end

  defp linked_account(account),
    do: %LinkedAccount{provider_account_id: account.uid, name: account.name, iban: account.iban}

  @doc """
  The bank connections, oldest first, with their accounts, the accounts these feed and their last five sync runs,
  newest first.
  """
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

  defp preload(connection),
    do:
      Repo.preload(connection, [linked_accounts: :account, sync_runs: recent_runs()], force: true)

  defp recent_runs do
    ranked =
      from r in SyncRun,
        select: %{
          id: r.id,
          rank:
            over(row_number(),
              partition_by: r.connection_id,
              order_by: [desc: r.started_at, desc: r.id]
            )
        }

    from r in SyncRun,
      join: x in subquery(ranked),
      on: x.id == r.id and x.rank <= @recent_runs,
      order_by: [desc: r.started_at, desc: r.id]
  end

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

  @doc """
  Fetches the connection's linked accounts and returns the sync run, or why it failed with a sentence; `trigger:` is
  `:manual` ("Jetzt abrufen", the default) or `:scheduled`. Only a manual fetch passes on `psu:` (see
  `Abakus.BankSync.Client`). A fetch of the connection that is still running refuses the next.
  """
  def fetch(%Scope{} = scope, %Connection{id: id}, opts \\ []) do
    owner!(scope)
    trigger = Keyword.get(opts, :trigger, :manual)
    psu = if trigger == :manual, do: Keyword.get(opts, :psu)

    case with_lock(id, fn -> fetch_unexpired(scope, get_connection!(scope, id), trigger, psu) end) do
      :locked -> {:error, "Der Abruf läuft schon."}
      result -> result
    end
  end

  defp fetch_unexpired(scope, connection, trigger, psu) do
    if Connection.expired?(connection),
      do: {:error, "Die Freigabe ist abgelaufen; nach dem Erneuern ruft Abakus wieder ab."},
      else: fetch_connection(scope, connection, trigger, psu)
  end

  @doc """
  Fetches every connection with a linked account and a consent that has not ended on schedule,
  `[{connection, result of fetch/3}]`.
  """
  def fetch_all(%Scope{} = scope) do
    for connection <- list_connections(scope), Connection.fetchable?(connection) do
      {connection, fetch(scope, connection, trigger: :scheduled)}
    end
  end

  defp with_lock(id, fun) do
    lock = {{__MODULE__, id}, self()}

    if :global.set_lock(lock, [node()], 0) do
      try do
        fun.()
      after
        :global.del_lock(lock, [node()])
      end
    else
      :locked
    end
  end

  defp fetch_connection(scope, connection, trigger, psu) do
    started_at = LocalTime.utc_now()

    results =
      for linked <- connection.linked_accounts,
          linked.account,
          do: {linked, fetch_account(scope, linked, psu)}

    error = fetch_error(results)

    run =
      struct!(
        %SyncRun{connection_id: connection.id, started_at: started_at, trigger: trigger},
        Map.put(fetch_counts(results), :error, error)
      )

    with {:ok, run} <- finish(run, connection_changes(results, error, started_at)),
         do: if(error, do: {:error, error}, else: {:ok, run})
  end

  defp fetch_counts(results) do
    for {_linked, {:ok, counts}} <- results,
        reduce: %{new: 0, matched: 0},
        do: (sum -> Map.merge(sum, counts, fn _key, a, b -> a + b end))
  end

  defp fetch_error(results) do
    case for(
           {linked, {:error, reason}} <- results,
           do: "#{linked.account.name}: #{error_message(reason)}"
         ) do
      [] -> nil
      errors -> Enum.join(errors, " ")
    end
  end

  defp connection_changes(results, error, started_at) do
    cond do
      error == nil ->
        %{last_error: nil, last_sync_at: started_at}

      Enum.any?(results, &match?({_linked, {:error, :consent_ended}}, &1)) ->
        %{last_error: error, valid_until: LocalTime.utc_now()}

      true ->
        %{last_error: error}
    end
  end

  defp finish(run, changes) do
    Repo.transact(fn ->
      case Repo.get(Connection, run.connection_id) do
        nil ->
          {:error, error_message(:unknown_connection)}

        connection ->
          Repo.update!(Ecto.Changeset.change(connection, changes))
          {:ok, Repo.insert!(run)}
      end
    end)
  end

  defp fetch_account(scope, linked, psu) do
    started = LocalTime.utc_now()
    uid = linked.provider_account_id
    from = date_from(linked)

    with :ok <- takes_entries(linked.account),
         {:ok, transactions} <- client().transactions(uid, from, psu),
         {:ok, balances} <- client().balances(uid, psu) do
      entries =
        Enum.filter(entries(transactions), &(Date.compare(&1.date, linked.start_date) != :lt))

      fetched = %{from: from, entries: entries, balances: balances}
      Repo.transact(fn -> import_account(scope, linked, fetched, started) end)
    end
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      {:error, :failed}
  catch
    :exit, reason ->
      Logger.error("Fetching bank account #{linked.id} exited: #{inspect(reason)}")
      {:error, :failed}
  end

  defp import_account(scope, linked, fetched, started) do
    with :ok <- remove_gone_pending(scope, linked.account, fetched),
         {:ok, counts} <- import_entries(scope, linked.account, fetched.entries),
         :ok <- put_bank_balance(scope, linked.account, fetched.balances) do
      # Only while it feeds the same account from the same date; reassigned meanwhile, it starts over.
      Repo.update_all(
        from(l in LinkedAccount,
          where:
            l.id == ^linked.id and l.account_id == ^linked.account_id and
              l.start_date == ^linked.start_date
        ),
        set: [last_fetch_at: started]
      )

      {:ok, counts}
    end
  end

  defp takes_entries(account) do
    if Account.takes_entries?(account),
      do: :ok,
      else: {:error, "Das Konto ist geschlossen oder nimmt keine Bankumsätze mehr."}
  end

  defp date_from(%LinkedAccount{last_fetch_at: nil, start_date: start_date}), do: start_date

  defp date_from(%LinkedAccount{last_fetch_at: last_fetch_at, start_date: start_date}),
    do: Enum.max([start_date, Date.add(LocalTime.date(last_fetch_at), -@refetch_days)], Date)

  # Not before the newest reconciled transaction, as the import skips the booked version there.
  defp remove_gone_pending(scope, account, %{from: from, entries: entries}) do
    reported = MapSet.new(entries, & &1.external_id)

    from =
      case Ledger.last_reconciled_date(scope, account) do
        nil -> from
        reconciled -> Enum.max([from, Date.add(reconciled, 1)], Date)
      end

    gone =
      for {external_id, transaction} <- Ledger.list_pending_imports(scope, account, :bank, from),
          external_id not in reported,
          do: transaction

    case Ledger.delete_transactions(scope, gone) do
      {:ok, _deleted} ->
        :ok

      {:error, _changeset} ->
        {:error,
         "Ein vorgemerkter Umsatz, den die Bank nicht mehr meldet, ließ sich nicht entfernen."}
    end
  end

  defp import_entries(scope, account, entries) do
    case Import.import(scope, account, :bank, entries) do
      {:ok, counts} ->
        {:ok, counts}

      {:error, {entry, _changeset}} ->
        {:error,
         "Der Umsatz vom #{Format.date(entry.date)} über #{Money.euros(entry.amount)} ließ sich nicht importieren."}
    end
  end

  @doc """
  The booked and pending transactions as import entries: the external id is the bank's entry reference, else its
  transaction id, else a key of date, amount and payee, numbered from the second on that repeats it (" 2"), for a
  pending one after `pending:`, so that its booked version never passes for it; the payee is the creditor of a debit, the debtor of a credit, else the first
  remittance line; the memo the remittance lines without their SEPA prefixes. Booked ones are cleared, pending ones
  uncleared. Those without a date or amount are left out, as are those neither booked nor pending.
  """
  def entries(transactions) do
    {entries, _keys} =
      for transaction <- transactions,
          transaction.status in [:booked, :pending],
          transaction.date != nil and transaction.amount != nil,
          reduce: {[], %{}} do
        {entries, keys} ->
          {entry, keys} = number(entry(transaction), transaction, keys)
          {[entry | entries], keys}
      end

    Enum.reverse(entries)
  end

  # Repeated keys are told apart by their order in the response, which keeps all transactions of their date.
  defp number(entry, %{entry_reference: nil, transaction_id: nil}, keys) do
    count = Map.get(keys, entry.external_id, 0) + 1
    numbered = if count == 1, do: entry.external_id, else: "#{entry.external_id} #{count}"
    {%{entry | external_id: numbered}, Map.put(keys, entry.external_id, count)}
  end

  defp number(entry, _bank_id, keys), do: {entry, keys}

  defp entry(%{status: :pending} = transaction) do
    entry = entry(%{transaction | status: :booked})

    %{
      entry
      | external_id: TransactionOrigin.pending_prefix() <> entry.external_id,
        cleared: :uncleared
    }
  end

  defp entry(transaction) do
    payee_name = payee_name(transaction)

    %{
      external_id:
        transaction.entry_reference || transaction.transaction_id ||
          key(transaction, payee_name),
      date: transaction.date,
      amount: transaction.amount,
      payee_name: payee_name,
      memo: memo(transaction.remittance),
      cleared: :cleared
    }
  end

  defp payee_name(%{amount: amount} = transaction) do
    counterparty =
      cond do
        amount < 0 -> transaction.creditor
        amount > 0 -> transaction.debtor
        true -> nil
      end

    counterparty || transaction.remittance |> remittance_lines() |> List.first()
  end

  defp memo(remittance) do
    case remittance_lines(remittance) do
      [] -> nil
      lines -> Enum.join(lines, " ")
    end
  end

  defp remittance_lines(remittance) do
    for line <- remittance,
        text = line |> String.replace(@sepa_prefixes, "") |> String.trim(),
        text != "",
        do: text
  end

  defp key(transaction, payee_name),
    do:
      "#{Date.to_iso8601(transaction.date)} #{transaction.amount} #{Names.lookup_key(payee_name || "")}"

  defp put_bank_balance(scope, account, balances) do
    case Import.put_bank_balance(scope, account, :bank, bank_balance(balances)) do
      :ok -> :ok
      {:error, _changeset} -> {:error, "Der Banksaldo ließ sich nicht speichern."}
    end
  end

  @doc "The bank balance among the bank's balances: the closing booked one, else the interim booked one; nil without."
  def bank_balance(balances) do
    balance =
      Enum.find(balances, &(&1.type == :closing_booked)) ||
        Enum.find(balances, &(&1.type == :interim_booked))

    balance && %{amount: balance.amount, date: balance.date || LocalTime.today()}
  end

  @doc "The connections whose consent has ended or ends within 14 days, oldest first, for the banner in Finanzen."
  def expiring_consents(%Scope{} = scope) do
    owner!(scope)
    today = LocalTime.today()

    from(c in owned(Connection, scope), order_by: c.id)
    |> Repo.all()
    |> Enum.filter(
      &(Connection.expired?(&1) or Connection.days_left(&1, today) <= @expiring_days)
    )
  end

  @doc """
  Whether a bank connection that is fetched (`Connection.fetchable?/1`) keeps failing: it has an error and no
  successful fetch for more than a day, counted from its creation when it never had one; never while bank sync is not
  set up. For the health check, with the system's scope.
  """
  def failing?(%Scope{system: true}) do
    a_day_ago = DateTime.add(LocalTime.utc_now(), -1, :day)

    available?() and
      from(c in Connection,
        where:
          not is_nil(c.last_error) and
            coalesce(c.last_sync_at, c.inserted_at) < type(^a_day_ago, :utc_datetime_usec),
        preload: :linked_accounts
      )
      |> Repo.all()
      |> Enum.any?(&Connection.fetchable?/1)
  end

  def failing?(%Scope{}), do: raise(AccessError)

  @doc "A sentence for why a request to the bank failed."
  def error_message(:not_configured), do: "Bank-Sync ist nicht eingerichtet."
  def error_message(:unknown_bank), do: "Diese Bank bietet Enable Banking nicht an."
  def error_message(:unknown_connection), do: "Die Bankverbindung gibt es nicht mehr."
  def error_message(:invalid_key), do: "Der private Schlüssel für Enable Banking ist ungültig."

  def error_message(:key_unreadable),
    do: "Die Datei mit dem privaten Schlüssel für Enable Banking lässt sich nicht lesen."

  def error_message(:timeout), do: "Enable Banking hat nicht rechtzeitig geantwortet."
  def error_message(:unreachable), do: "Enable Banking ist nicht erreichbar."
  def error_message(:too_large), do: "Die Antwort von Enable Banking ist zu groß."
  def error_message(:invalid_response), do: "Enable Banking hat unerwartet geantwortet."

  def error_message(:rate_limited),
    do: "Die Bank hat den Abruf abgelehnt: für heute waren es zu viele Abrufe."

  def error_message(:consent_ended),
    do: "Die Bank hat den Abruf abgelehnt: die Freigabe gilt nicht mehr."

  def error_message(:failed), do: "Der Abruf ist unerwartet fehlgeschlagen."

  def error_message({:http_status, status}),
    do: "Enable Banking hat die Anfrage abgelehnt (HTTP #{status})."

  def error_message(message) when is_binary(message), do: message

  defp owner!(scope) do
    if Scope.budget_owner?(scope), do: scope, else: raise(AccessError)
  end

  defp client, do: Application.fetch_env!(:abakus, __MODULE__)[:client]
end

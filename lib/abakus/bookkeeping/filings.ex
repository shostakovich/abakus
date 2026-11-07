defmodule Abakus.Bookkeeping.Filings do
  @moduledoc """
  The returns the user sends to ELSTER (`Abakus.Bookkeeping.Elster`), each kept as a `Abakus.Bookkeeping.Filing`
  with ELSTER's protocol.

  A return is named by its period: `{:vat_quarter, year, quarter}` for a quarter's Voranmeldung,
  `{:vat_year, year}` for a year's Umsatzsteuererklärung and `{:euer, year}` for its EÜR. It can be sent once its
  period is over, and only once. Sending locks its period: a change to a tax line or a disposal dated in it, to the
  payment linked to a sale there and, for an EÜR, to what an asset counts for in its year is refused with
  `locked_message/0`, and its transactions leave the inbox. The Ledger stays open: an edit to a transaction there
  changes the computed return, which then shows as a difference to the one sent (`matches?/2`). A send first reserves
  its period, so that a second one is refused before it reaches ELSTER; a failed send frees it and locks nothing, and
  a restart frees the period of a send it interrupted. The PIN is asked at every send and passed on to ELSTER, never
  stored or logged.

  A return filed elsewhere, before Abakus, is locked by its period as a filing without Kennzahlen or protocol
  (`lock_filed_elsewhere/2`). It locks its tax lines and cannot be sent, but leaves the asset register open: its
  assets and disposals did not come over and are recorded afterwards.
  """

  import Ecto.Query
  import Abakus.Owned

  require Logger

  alias Abakus.Bookkeeping.{
    Elster,
    Filing,
    IncomeStatement,
    IncomeStatements,
    Settings,
    States,
    VatReturn,
    VatReturns
  }

  alias Abakus.Bookkeeping.Elster.Xml
  alias Abakus.{Ids, LocalTime, Repo}
  alias Abakus.Users.Scope

  @locked "Zeitraum ist festgeschrieben"

  @typedoc "The period that names a return."
  @type period ::
          {:vat_quarter, integer, 1..4} | {:vat_year, integer} | {:euer, integer}

  @doc "Why a change to a locked period is refused."
  def locked_message, do: @locked

  @doc "Whether a sent return covers `date`."
  def locked?(%Scope{} = scope, %Date{} = date),
    do: Repo.exists?(from f in filed(scope), where: f.first <= ^date and f.last >= ^date)

  @doc "Whether a return sent from Abakus covers `date`, which locks the disposals dated there."
  def register_locked?(%Scope{} = scope, %Date{} = date),
    do:
      Repo.exists?(
        from f in filed(scope),
          where: f.first <= ^date and f.last >= ^date and not f.filed_elsewhere
      )

  @doc "A condition for a query of transactions: dated in a period a sent return locks."
  def locked_date(%Scope{} = scope) do
    scope
    |> owned_spans()
    |> Enum.reduce(dynamic(false), fn {first, last}, locked ->
      dynamic([t], ^locked or (t.date >= ^first and t.date <= ^last))
    end)
  end

  defp filed(scope), do: from(f in owned(Filing, scope), where: not f.pending)

  defp owned_spans(scope), do: Repo.all(from f in filed(scope), select: {f.first, f.last})

  @doc "The years whose EÜR was sent from Abakus."
  def euer_years(%Scope{} = scope) do
    firsts =
      Repo.all(
        from f in filed(scope),
          where: f.kind == :euer and not f.filed_elsewhere,
          select: f.first
      )

    Enum.map(firsts, & &1.year)
  end

  @doc """
  Locks the return of each of `periods` that is over as filed elsewhere, unless it was sent already; those over.
  """
  @spec lock_filed_elsewhere(Scope.t(), [period]) :: [period]
  def lock_filed_elsewhere(%Scope{} = scope, periods) do
    now = Abakus.Schema.usec(LocalTime.utc_now())
    over = Enum.filter(periods, &over?/1)

    rows =
      for period <- over do
        {first, last} = span(period)

        %{
          id: Ids.generate(),
          user_id: user_id(scope),
          kind: elem(period, 0),
          first: first,
          last: last,
          kennzahlen: %{},
          filed_elsewhere: true,
          sent_at: now,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Filing, rows,
      on_conflict: :nothing,
      conflict_target: [:user_id, :kind, :first]
    )

    over
  end

  @doc "The last period of `kind` (`:vat_quarter` or `:euer`) locked as filed elsewhere, nil if none is."
  def filed_elsewhere_through(%Scope{} = scope, kind) when kind in [:vat_quarter, :euer] do
    Repo.one(
      from f in filed(scope),
        where: f.filed_elsewhere and f.kind == ^kind,
        order_by: [desc: f.first],
        limit: 1
    )
    |> then(&(&1 && period(&1)))
  end

  @doc "The sent return of `period`, without its protocol; nil if there is none."
  def sent(%Scope{} = scope, period) do
    {first, _last} = span(period)
    kind = elem(period, 0)

    Repo.one(
      from f in filed(scope),
        where: f.kind == ^kind and f.first == ^first,
        select: %{f | protocol: nil}
    )
  end

  @doc "The filing with `id`, with its protocol."
  def get(%Scope{} = scope, id) do
    case Ids.cast(id) do
      {:ok, id} -> Repo.one(from f in filed(scope), where: f.id == ^id)
      :error -> nil
    end
  end

  @doc """
  What the return of `period` is called: `Voranmeldung 1. Quartal 2027`, `Umsatzsteuererklärung 2027`, `EÜR 2027`.
  """
  def title({:vat_quarter, year, quarter}), do: "Voranmeldung #{quarter}. Quartal #{year}"
  def title({:vat_year, year}), do: "Umsatzsteuererklärung #{year}"
  def title({:euer, year}), do: "EÜR #{year}"

  @doc "The protocol's file name: `Übertragungsprotokoll Voranmeldung 1. Quartal 2027.pdf`."
  def protocol_filename(%Filing{} = filing),
    do: "Übertragungsprotokoll #{title(period(filing))}.pdf"

  defp period(%Filing{kind: :vat_quarter, first: first}),
    do: {:vat_quarter, first.year, div(first.month + 2, 3)}

  defp period(%Filing{kind: kind, first: first}), do: {kind, first.year}

  @doc "Whether the Kennzahlen of the computed return are those the filing sent."
  def matches?(%Filing{kennzahlen: sent}, computed), do: sent == stored(computed)

  @doc """
  What sending a return of `kind` (`:vat` or `:euer`) still lacks, as the settings name it: none when it can be
  sent. ELSTER not set up on the server comes first.
  """
  def missing(%Scope{} = scope, kind) do
    server = if Elster.available?(), do: [], else: ["ELSTER auf dem Server"]
    server ++ Settings.missing_for_elster(Settings.get_settings(scope), kind)
  end

  @doc "What sending the return of `period` lacks in the settings, as `missing/2`."
  def missing_for(%Scope{} = scope, period), do: missing(scope, settings_kind(period))

  defp settings_kind({:euer, _year}), do: :euer
  defp settings_kind(_vat), do: :vat

  @doc "Whether the period of `period` is over, so that its return can be sent."
  def over?(period) do
    {_first, last} = span(period)
    Date.before?(last, LocalTime.today())
  end

  @doc "The return of `period`, computed from the user's books."
  def compute(%Scope{} = scope, {:vat_quarter, year, quarter}),
    do: VatReturns.quarter(scope, year, quarter)

  def compute(%Scope{} = scope, {:vat_year, year}), do: VatReturns.year(scope, year)
  def compute(%Scope{} = scope, {:euer, year}), do: IncomeStatements.year(scope, year)

  @doc """
  Sends the return of `period` to ELSTER with the certificate's `pin`, keeps ELSTER's protocol and locks the period.
  `{:error, message}` says why it was not sent.
  """
  def send_return(%Scope{} = scope, period, pin) when is_binary(pin) do
    computed = compute(scope, period)

    with :ok <- check_sendable(scope, period, computed, pin),
         {:ok, reserved} <- reserve(scope, period, computed) do
      case submit_reserved(scope, period, computed, pin, reserved) do
        {:ok, receipt} ->
          finish(scope, period, reserved, receipt)

        {:error, message} ->
          Repo.delete!(reserved)
          {:error, message}
      end
    end
  end

  @doc "Frees the periods of the sends a restart interrupted; ELSTER may have taken them."
  def release_interrupted do
    for filing <- Repo.all(from f in Filing, where: f.pending) do
      Logger.warning(
        "Freed the #{title(period(filing))} of user #{filing.user_id}, whose send was interrupted; " <>
          "ELSTER may have taken it"
      )

      Repo.delete!(filing)
    end

    :ok
  end

  defp check_sendable(scope, period, computed, pin) do
    missing = missing_for(scope, period)

    cond do
      not over?(period) -> {:error, not_over(period)}
      sent(scope, period) -> {:error, @locked}
      missing != [] -> {:error, "Es fehlt: #{Enum.join(missing, ", ")}."}
      String.trim(pin) == "" -> {:error, "Bitte die PIN des Zertifikats eingeben."}
      other_rates?(computed) -> {:error, "Umsätze zu anderen Steuersätzen sendet Abakus nicht."}
      true -> :ok
    end
  end

  defp not_over({:vat_quarter, _year, _quarter}), do: "Das Quartal ist noch nicht vorbei."
  defp not_over(_year), do: "Das Jahr ist noch nicht vorbei."

  defp other_rates?(%VatReturn{quarter: nil, lines: lines}),
    do: Enum.any?(lines, &(&1.key == :sales_other and (&1.base != 0 or &1.tax != 0)))

  defp other_rates?(_computed), do: false

  defp submit(scope, period, computed, pin) do
    settings = Settings.get_settings(scope)

    submission = %{
      tax_number: settings.tax_number,
      state_number: States.number(settings.tax_state),
      xml: fn elster_tax_number ->
        xml(period, computed, settings, elster_tax_number,
          vendor_id: Elster.vendor_id(),
          test: Elster.test?(),
          created_on: LocalTime.today()
        )
      end,
      datenart_version: Xml.datenart_version(computed),
      certificate: settings.elster_certificate,
      pin: fn -> pin end
    }

    case Elster.client().submit(submission) do
      {:ok, receipt} ->
        {:ok, receipt}

      {:error, message} ->
        Logger.warning(
          "ELSTER refused the #{title(period)} of user #{user_id(scope)}: #{message}"
        )

        {:error, message}
    end
  end

  defp xml({:vat_quarter, _year, _quarter}, computed, settings, tax_number, opts),
    do: Xml.vat_quarter(computed, settings, tax_number, opts)

  defp xml({:vat_year, _year}, computed, settings, tax_number, opts),
    do: Xml.vat_year(computed, settings, tax_number, opts)

  defp xml({:euer, _year}, computed, settings, tax_number, opts),
    do: Xml.euer(computed, settings, tax_number, opts)

  defp reserve(scope, period, computed) do
    {first, last} = span(period)

    %Filing{
      user_id: user_id(scope),
      kind: elem(period, 0),
      first: first,
      last: last,
      kennzahlen: stored(computed),
      sent_at: Abakus.Schema.usec(LocalTime.utc_now()),
      pending: true
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint([:user_id, :kind, :first])
    |> Repo.insert()
    |> case do
      {:ok, reserved} -> {:ok, reserved}
      {:error, _changeset} -> {:error, taken(scope, period)}
    end
  end

  defp taken(scope, period),
    do: if(sent(scope, period), do: @locked, else: "Die #{title(period)} wird gerade gesendet.")

  defp submit_reserved(scope, period, computed, pin, reserved) do
    submit(scope, period, computed, pin)
  catch
    kind, reason ->
      Repo.delete!(reserved)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp finish(scope, period, reserved, receipt) do
    reserved
    |> Ecto.Changeset.change(
      transfer_ticket: receipt.transfer_ticket,
      protocol: receipt.protocol,
      sent_at: Abakus.Schema.usec(LocalTime.utc_now()),
      pending: false
    )
    |> Repo.update!()
    |> then(&{:ok, &1})
  rescue
    exception ->
      Logger.error(
        "ELSTER took the #{title(period)} of user #{user_id(scope)} with transfer ticket " <>
          "#{receipt.transfer_ticket}, but it was not stored: #{Exception.message(exception)}"
      )

      {:error,
       "ELSTER hat die #{title(period)} angenommen (Transferticket #{receipt.transfer_ticket}), " <>
         "Abakus konnte sie aber nicht speichern."}
  end

  defp span({:vat_quarter, year, quarter}), do: VatReturn.quarter_span(year, quarter)
  defp span({_annual, year}), do: {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}

  defp stored(%VatReturn{} = vat_return), do: by_text(VatReturn.kennzahlen(vat_return))

  defp stored(%IncomeStatement{} = statement),
    do: by_text(IncomeStatement.kennzahlen(statement))

  defp by_text(kennzahlen),
    do: Map.new(kennzahlen, fn {kennzahl, value} -> {"#{kennzahl}", value} end)
end

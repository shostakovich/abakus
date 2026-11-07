defmodule Abakus.Bookkeeping.Filings do
  @moduledoc """
  The returns the user sends to ELSTER (`Abakus.Bookkeeping.Elster`), each kept as a `Abakus.Bookkeeping.Filing`
  with ELSTER's protocol, and the ELSTER certificate of their settings.

  A quarter's Voranmeldung can be sent once the quarter is over, and only once. Sending locks its period: what would
  change the return, a tax line or a disposal dated in it, is refused with `locked_message/0`, and its transactions
  leave the inbox. A failed send locks nothing. The PIN is asked at every send and passed on to ELSTER, never stored
  or logged.
  """

  import Ecto.Query
  import Abakus.Owned

  require Logger

  alias Abakus.Bookkeeping.{Elster, Filing, Invoices, Settings, States, VatReturn, VatReturns}
  alias Abakus.Bookkeeping.Elster.Xml
  alias Abakus.{Ids, LocalTime, Repo}
  alias Abakus.Users.Scope

  @locked "Zeitraum ist festgeschrieben"

  @doc "Why a change to a locked period is refused."
  def locked_message, do: @locked

  @doc "Whether a sent return covers `date`."
  def locked?(%Scope{} = scope, %Date{} = date),
    do: Repo.exists?(from f in owned(Filing, scope), where: f.first <= ^date and f.last >= ^date)

  @doc "The first and last day of every period a sent return locks."
  def locked_spans(%Scope{} = scope),
    do: Repo.all(from f in owned(Filing, scope), select: {f.first, f.last})

  @doc "The sent Voranmeldung of `quarter` of `year`, nil if there is none."
  def vat_quarter(%Scope{} = scope, year, quarter) do
    {first, _last} = VatReturn.quarter_span(year, quarter)

    Repo.one(
      from f in owned(Filing, scope),
        where: f.kind == :vat_quarter and f.first == ^first,
        select: %{f | protocol: nil}
    )
  end

  @doc "The filing with `id`, with its protocol."
  def get(%Scope{} = scope, id) do
    case Ids.cast(id) do
      {:ok, id} -> Repo.one(from f in owned(Filing, scope), where: f.id == ^id)
      :error -> nil
    end
  end

  @doc "The protocol's file name: `Übertragungsprotokoll Voranmeldung 2027 Q1.pdf`."
  def protocol_filename(%Filing{kind: :vat_quarter, first: first}),
    do: "Übertragungsprotokoll Voranmeldung #{first.year} Q#{div(first.month + 2, 3)}.pdf"

  @doc "Whether the Kennzahlen of `vat_return` are those the filing sent."
  def matches?(%Filing{kennzahlen: sent}, %VatReturn{} = vat_return),
    do: sent == stored(vat_return)

  @doc "Stores the ELSTER certificate, `{content, filename}` of a .pfx file."
  def put_certificate(%Scope{} = scope, {_content, _filename} = certificate),
    do: save_certificate(scope, certificate)

  @doc "Forgets the ELSTER certificate."
  def remove_certificate(%Scope{} = scope), do: save_certificate(scope, nil)

  defp save_certificate(scope, certificate) do
    scope
    |> Invoices.get_settings()
    |> Settings.certificate_changeset(certificate)
    |> Repo.insert_or_update()
  end

  @doc """
  What sending still lacks, as the settings name it: none when a return can be sent. ELSTER not set up on the
  server comes first.
  """
  def missing(%Scope{} = scope) do
    server = if Elster.available?(), do: [], else: ["ELSTER auf dem Server"]
    server ++ Settings.missing_for_elster(Invoices.get_settings(scope))
  end

  @doc "Whether the quarter is over, so that its Voranmeldung can be sent."
  def over?(%VatReturn{last: last}), do: Date.before?(last, LocalTime.today())

  @doc """
  Sends the Voranmeldung of `quarter` of `year` to ELSTER with the certificate's `pin`, keeps ELSTER's protocol and
  locks the quarter. `{:error, message}` says why it was not sent.
  """
  def send_vat_quarter(%Scope{} = scope, year, quarter, pin) when is_binary(pin) do
    vat_return = VatReturns.quarter(scope, year, quarter)

    with :ok <- check_sendable(scope, vat_return, pin),
         {:ok, receipt} <- submit(scope, vat_return, pin) do
      insert(scope, vat_return, receipt)
    end
  end

  defp check_sendable(scope, vat_return, pin) do
    missing = missing(scope)

    cond do
      not over?(vat_return) -> {:error, "Das Quartal ist noch nicht vorbei."}
      vat_quarter(scope, vat_return.year, vat_return.quarter) -> {:error, @locked}
      missing != [] -> {:error, "Es fehlt: #{Enum.join(missing, ", ")}."}
      String.trim(pin) == "" -> {:error, "Bitte die PIN des Zertifikats eingeben."}
      true -> :ok
    end
  end

  defp submit(scope, vat_return, pin) do
    settings = Invoices.get_settings(scope)

    submission = %{
      tax_number: settings.tax_number,
      state_number: States.number(settings.tax_state),
      xml: fn elster_tax_number ->
        Xml.vat_quarter(vat_return, settings, elster_tax_number,
          vendor_id: Elster.vendor_id(),
          test: Elster.test?(),
          created_on: LocalTime.today()
        )
      end,
      datenart_version: Xml.datenart_version(vat_return),
      certificate: settings.elster_certificate,
      pin: fn -> pin end
    }

    case Elster.client().submit(submission) do
      {:ok, receipt} ->
        {:ok, receipt}

      {:error, message} ->
        Logger.warning(
          "ELSTER refused the Voranmeldung #{vat_return.year} Q#{vat_return.quarter} of user " <>
            "#{user_id(scope)}: #{message}"
        )

        {:error, message}
    end
  end

  defp insert(scope, vat_return, receipt) do
    %Filing{
      user_id: user_id(scope),
      kind: :vat_quarter,
      first: vat_return.first,
      last: vat_return.last,
      kennzahlen: stored(vat_return),
      transfer_ticket: receipt.transfer_ticket,
      protocol: receipt.protocol,
      sent_at: Abakus.Schema.usec(LocalTime.utc_now())
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint([:user_id, :kind, :first])
    |> Repo.insert()
    |> case do
      {:ok, filing} -> {:ok, filing}
      {:error, _changeset} -> {:error, @locked}
    end
  end

  defp stored(vat_return),
    do:
      Map.new(VatReturn.kennzahlen(vat_return), fn {kennzahl, value} -> {"#{kennzahl}", value} end)
end

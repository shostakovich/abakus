defmodule Abakus.Depot.Receipts do
  @moduledoc """
  The inbox („Eingang“): uploaded PDF receipts and those from the user's Paperless, which a
  language model on the user's own server reads in the background (ADR 0015), with the checks of
  what it recognised, until the user books or discards them. Open pages hear about every change
  over PubSub.

  A file already in the inbox or booked never lands twice; a discarded one comes back when uploaded
  again, not from Paperless. Receipts
  still being recognised when the app stops are recognised again when it starts.
  """

  import Ecto.Query

  require Logger

  alias Abakus.Depot.{Portfolios, Settings}
  alias Abakus.Depot.Portfolios.{Portfolio, Receipt, Transaction}
  alias Abakus.Depot.Receipts.{Checks, Correction, Fields, Recognition}
  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Settings.Setting
  alias Abakus.Repo
  alias Abakus.Users.Scope

  # Receipts are a page or two; anything longer is not a receipt the model needs to read whole.
  @max_text 20_000

  # As for an upload.
  @max_file_size 20_000_000

  @instructions """
  You read the text of a German bank's securities receipt and fill in its fields.

  kind: purchase (Kauf, also a savings plan: Sparplan), sale (Verkauf, also the repayment of a
  fund or bond at its end: Laufzeitende, Rückzahlung, Tilgung) or dividend (Dividende,
  Ausschüttung, Ertragsgutschrift).
  other for any other document, such as a statement of account, a tax report or an advance lump
  sum (Vorabpauschale).
  date: of a purchase or sale the trade day (Schlusstag, Handelstag, Geschäftstag, Ausführung),
  of a dividend the payment day (Zahltag, zahlbar ab, Valuta, Wertstellung); never the day the
  receipt was written nor the booking day (Buchung).
  shares: the number of shares or units, labelled Stück, St., Stk., STK, Anzahl, Berechtigte
  Anzahl, Bestand, Nominale or Nennwert, the number before or after the label, as in
  „St. 8,261“, „STK 12,000“, „0,585137 Stk.“ or „Anzahl 1.200“. Never a price or an amount of
  money: in „St. 7 EUR 315,25“ the shares are 7 and the price 315,25.
  price: the price per share (Ausführungskurs, Kurs, Preis), never the total (Kurswert); of a
  dividend the dividend per share (Dividende pro Stück, Ausschüttung pro Stück, Betrag / Stk.).
  fees: the sum of the commission and charge lines (Provision, Orderentgelt, Ordergebühren,
  Börsengebühr, Handelsplatzgebühr, fremde Spesen).
  taxes: the sum of the taxes withheld (Kapitalertragsteuer, Solidaritätszuschlag,
  Kirchensteuer, Quellensteuer, Finanztransaktionssteuer); not a tax only mentioned, such as
  „anrechenbare Quellensteuer“.
  amount: the final amount charged to or credited to the account after fees and taxes
  (Ausmachender Betrag, Endbetrag, Belastung, Gesamtbetrag, Total, „zu Ihren Gunsten nach
  Steuern“); where the receipt states such an amount, never one before taxes. Where taxes come
  on a separate tax notice (separate Steuermitteilung) and the receipt states only the amount
  before taxes („zu Ihren Lasten/Gunsten vor Steuern“), that amount, and taxes 0.
  bank_reference: the receipt's own reference or order number (Referenz, Ordernummer,
  Auftragsnummer, Abrechnungsnummer); never an account number.

  Copy each number exactly as the receipt prints it, as „8,261“ or „1.691,55“, without currency
  or sign; give a sum you add up in the same notation. Amounts are in the receipt's currency.
  Give dates as YYYY-MM-DD. Give null only for a field the receipt does not state.
  """

  @doc "Subscribes the caller to changes of the user's inbox, sent as `:receipts_updated`."
  def subscribe(%Scope{} = scope),
    do: Phoenix.PubSub.subscribe(Abakus.PubSub, topic(scope.user.id))

  defp broadcast(user_id),
    do: Phoenix.PubSub.broadcast(Abakus.PubSub, topic(user_id), :receipts_updated)

  defp topic(user_id), do: "receipts:#{user_id}"

  @doc "The receipts in the user's inbox, newest first."
  def list_inbox(%Scope{} = scope) do
    Repo.all(
      from r in inbox_query(scope),
        order_by: [desc: r.inserted_at, desc: r.id]
    )
  end

  @doc "How many receipts in the user's inbox are recognised: those still being read wait."
  def inbox_count(%Scope{} = scope),
    do: Repo.aggregate(from(r in inbox_query(scope), where: r.status != :recognising), :count)

  defp inbox_query(scope) do
    from r in Receipt,
      where: r.user_id == ^scope.user.id and r.status in ^Receipt.inbox_statuses()
  end

  @doc "A recognised receipt in the user's inbox, ready to book, with its checks as of now."
  def get_ready_receipt(%Scope{} = scope, id) do
    case Repo.get_by(Receipt, id: id, user_id: scope.user.id, status: :ready) do
      nil -> nil
      receipt -> %{receipt | checks: checks(receipt)}
    end
  end

  @doc """
  Puts the PDF at `path` into the user's inbox and recognises it in the background. Returns
  `{:ok, :added}`, or for a file the user uploaded before `{:ok, :in_inbox}` or `{:ok, :booked}`;
  a discarded one comes back as added. `{:error, :not_pdf}` for any other file.
  """
  def upload(%Scope{} = scope, path, filename),
    do: take(scope, File.read!(path), [filename: filename], :bring_back)

  defp take(scope, content, attrs, discarded) do
    with {:ok, sha256} <- Portfolios.store_receipt_file(content) do
      case Repo.get_by(Receipt, user_id: scope.user.id, sha256: sha256) do
        nil ->
          add(scope, [sha256: sha256, byte_size: byte_size(content)] ++ attrs)

        %Receipt{status: :discarded} = receipt when discarded == :bring_back ->
          recognise_again(receipt, attrs)

        %Receipt{status: :discarded} ->
          {:ok, :discarded}

        %Receipt{status: :booked} ->
          {:ok, :booked}

        _in_inbox ->
          {:ok, :in_inbox}
      end
    end
  end

  # The same file taken at the same time, say uploaded while Paperless is polled, lands once.
  defp add(scope, attrs) do
    case Repo.insert(struct!(%Receipt{user_id: scope.user.id, status: :recognising}, attrs),
           on_conflict: :nothing,
           conflict_target: [:user_id, :sha256]
         ) do
      {:ok, %Receipt{id: nil}} ->
        {:ok, :in_inbox}

      {:ok, receipt} ->
        recognise_in_background(receipt)
        broadcast(scope.user.id)
        {:ok, :added}
    end
  end

  defp recognise_again(receipt, attrs) do
    receipt
    |> Ecto.Changeset.change([status: :recognising, text: nil, bank_reference: nil] ++ attrs)
    |> Ecto.Changeset.put_embed(:fields, nil)
    |> Ecto.Changeset.put_embed(:checks, [])
    |> Repo.update!()
    |> recognise_in_background()

    broadcast(receipt.user_id)
    {:ok, :added}
  end

  @doc """
  Puts the documents with the user's tag from the user's Paperless into the inbox, assigned to
  the user, with Paperless' text, and once a document is there swaps its tag for
  „<tag>-erledigt“; a document the inbox has already, or which was discarded, only loses its
  tag. Notes the time of the poll; a document that fails, or is larger than an upload may be,
  stays tagged for the next one.
  """
  def poll_paperless(%Setting{} = setting) do
    %Setting{user: user} = setting = Repo.preload(setting, :user)
    connection = %{url: setting.paperless_url, token: setting.paperless_token}

    case paperless().documents(connection, setting.paperless_tag) do
      {:ok, documents} ->
        Enum.each(documents, &take_document(setting, connection, &1))
        :ok = Settings.paperless_polled(setting)
        broadcast(user.id)

      {:error, reason} ->
        Logger.warning("polling Paperless of user #{user.id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "The tag a Paperless document gets once its receipt is in the inbox."
  def done_tag(tag), do: tag <> "-erledigt"

  defp take_document(%Setting{user: user} = setting, connection, document) do
    with {:ok, content} <- paperless().download(connection, document.id),
         :ok <- if(byte_size(content) > @max_file_size, do: {:error, :too_large}, else: :ok),
         {:ok, _added_or_known} <-
           take(
             Scope.for_user(user),
             content,
             [
               filename: document.filename || "Paperless #{document.id}.pdf",
               paperless_id: document.id,
               text: present(document.content)
             ],
             :keep_discarded
           ),
         :ok <-
           paperless().swap_tag(
             connection,
             document,
             setting.paperless_tag,
             done_tag(setting.paperless_tag)
           ) do
      :ok
    else
      {:error, reason} -> log_document(user, document, inspect(reason))
    end
  rescue
    exception -> log_document(user, document, Exception.message(exception))
  end

  defp log_document(user, document, reason),
    do: Logger.warning("Paperless document #{document.id} of user #{user.id}: #{reason}")

  defp present(text) when is_binary(text), do: if(String.trim(text) != "", do: text)
  defp present(nil), do: nil

  @doc "The model that recognises receipts, nil when none is configured."
  def model_name, do: model().name()

  @doc "When the user's Paperless was polled last, nil without one or before the first poll."
  def paperless_polled_at(%Scope{} = scope) do
    setting = Settings.get_settings(scope)
    if Setting.paperless?(setting), do: setting.paperless_polled_at
  end

  @doc "Discards a receipt of the user's inbox; it comes back when uploaded again."
  def discard(%Scope{} = scope, id) do
    {count, _receipts} =
      Repo.update_all(
        from(r in inbox_query(scope), where: r.id == ^id),
        set: [status: :discarded, updated_at: DateTime.utc_now()]
      )

    broadcast(scope.user.id)
    if count == 1, do: :ok, else: {:error, :gone}
  end

  @doc """
  Books the transaction form with `attrs` from a ready `receipt`, see
  `Portfolios.book_transaction/4`, and checks the receipts left in the inbox again.
  """
  def book(%Scope{} = scope, choices, attrs, %Receipt{} = receipt) do
    with {:ok, transactions} <- Portfolios.book_transaction(scope, choices, attrs, receipt) do
      recheck(scope)
      {:ok, transactions}
    end
  end

  @doc """
  Checks the recognised receipts in the user's inbox again, as a booked receipt, a new security
  or a changed depot number changes their checks.
  """
  def recheck(%Scope{} = scope) do
    for receipt <- Repo.all(from r in inbox_query(scope), where: r.status == :ready),
        receipt.fields,
        checks = checks(receipt),
        checks != receipt.checks do
      receipt
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:checks, checks)
      |> Repo.update!()
    end

    broadcast(scope.user.id)
  end

  @doc "Recognises, in the background, the receipts that were still being recognised at the stop."
  def resume_recognition do
    Repo.all(from r in Receipt, where: r.status == :recognising)
    |> Enum.each(&recognise_in_background/1)
  end

  defp recognise_in_background(receipt) do
    Recognition.enqueue(receipt.id)
    receipt
  end

  @doc """
  Reads the text of the receipt with `id`, unless Paperless gave it, has the model recognise its
  fields and checks them; nothing for a receipt no longer being recognised. A receipt the model
  cannot read, or any trouble on the way, leaves it ready with an empty form.
  """
  def recognise(id) do
    with %Receipt{status: :recognising} = receipt <- Repo.get(Receipt, id) do
      recognise_receipt(receipt)
    end

    :ok
  end

  defp recognise_receipt(receipt) do
    text = receipt.text || extract_text(receipt)
    fields = text && recognise_text(text)
    finish(receipt, text, fields)
  rescue
    exception ->
      Logger.error("recognising receipt #{receipt.id} failed: " <> Exception.message(exception))
      finish(receipt, nil, nil)
  catch
    :exit, reason ->
      Logger.error("recognising receipt #{receipt.id} failed: #{inspect(reason)}")
      finish(receipt, nil, nil)
  end

  defp extract_text(receipt) do
    case text_extractor().text(Portfolios.receipt_file(receipt)) do
      {:ok, text} -> text
      :error -> nil
    end
  end

  defp recognise_text(text) do
    if model().available?() do
      case read_fields(text, model()) do
        {:ok, fields, _correction} ->
          fields

        {:error, :off_schema} ->
          Logger.warning("the receipt model answered off the schema")
          nil

        {:error, reason} ->
          Logger.warning("the receipt model failed: #{inspect(reason)}")
          nil
      end
    end
  end

  @doc """
  The fields `model` recognises in a receipt's `text`, as the inbox reads them, and how a
  correction round went. When the amount does not add up, shares, price or amount are missing
  or the ISIN's check digit is wrong, the model hears so in the same chat, with any values not
  in the text, and answers once more; the answer scoring more on `Checks.correctable/2` is kept,
  the first on a tie, where a failed check scores below a passed one and above a missing one.
  The round is `:none` when it did not run, `:fixed` when the answer kept passes the amount and
  ISIN, `:unfixed` otherwise. `correction: false` skips it. `{:error, :off_schema}` for a first answer off the
  schema. The model copies numbers as printed; they are read in the notation of `text`.
  """
  def read_fields(text, model, options \\ []) do
    conversation = [{:user, String.slice(text, 0, @max_text)}]

    notation = Fields.notation(text)

    with {:ok, answer, fields} <- ask(model, conversation, notation) do
      checks = Checks.correctable(fields, text)

      if Keyword.get(options, :correction, true) and Checks.correction_needed?(checks) do
        conversation =
          conversation ++ [{:assistant, answer}, {:user, Correction.message(checks, fields)}]

        correct(model, conversation, {fields, checks}, text, notation)
      else
        {:ok, fields, :none}
      end
    end
  end

  defp ask(model, conversation, notation) do
    with {:ok, answer} <- model.answer(@instructions, conversation, Fields.json_schema()) do
      case Fields.from_answer(answer, notation) do
        {:ok, fields} -> {:ok, answer, fields}
        :error -> {:error, :off_schema}
      end
    end
  end

  defp correct(model, conversation, {fields, checks}, text, notation) do
    case ask(model, conversation, notation) do
      {:ok, _answer, corrected} ->
        corrected_checks = Checks.correctable(corrected, text)

        cond do
          passed(corrected_checks) <= passed(checks) -> {:ok, fields, :unfixed}
          Checks.correction_needed?(corrected_checks) -> {:ok, corrected, :unfixed}
          true -> {:ok, corrected, :fixed}
        end

      {:error, reason} ->
        Logger.warning("the receipt model's correction failed: #{inspect(reason)}")
        {:ok, fields, :unfixed}
    end
  end

  # A value that fails a check is worth more than none: the screen shows what to fix.
  defp passed(checks), do: Enum.sum_by(checks, &score(&1.result))

  defp score(:passed), do: 2
  defp score(:failed), do: 1
  defp score(_missing), do: 0

  # Only a receipt still being recognised takes the result; it may be gone or discarded meanwhile,
  # also between reading and writing it.
  defp finish(receipt, text, fields) do
    with %Receipt{status: :recognising} = current <- Repo.get(Receipt, receipt.id),
         {:ok, _finished} <-
           current
           |> Ecto.Changeset.change(
             status: if(match?(%Fields{kind: :other}, fields), do: :unsupported, else: :ready),
             text: text,
             bank_reference: fields && Receipt.bank_reference(fields.bank_reference)
           )
           |> Ecto.Changeset.put_embed(:fields, fields)
           |> Ecto.Changeset.put_embed(:checks, fields_checks(%{current | text: text}, fields))
           |> Map.update!(:filters, &Map.put(&1, :status, :recognising))
           |> Repo.update(stale_error_field: :status) do
      broadcast(receipt.user_id)
    end

    :ok
  end

  defp fields_checks(_receipt, nil), do: []
  defp fields_checks(_receipt, %Fields{kind: :other}), do: []

  defp fields_checks(receipt, fields),
    do:
      Checks.run(
        fields,
        receipt.text,
        known_isins(),
        portfolios_by_depot_number(receipt.user_id),
        &booked_on(receipt, &1)
      )

  defp checks(%Receipt{fields: fields} = receipt), do: fields_checks(receipt, fields)

  defp known_isins do
    MapSet.new(Repo.all(from s in Security, where: not is_nil(s.isin), select: s.isin))
  end

  # The user's active portfolios with a depot number, by its digits.
  defp portfolios_by_depot_number(user_id) do
    Repo.all(
      from p in Portfolio,
        where: p.user_id == ^user_id and not p.retired and not is_nil(p.depot_number)
    )
    |> Map.new(&{Portfolio.digits(&1.depot_number), &1})
  end

  # The day of the transaction booked from another receipt of the user with `reference`.
  defp booked_on(receipt, reference) do
    case Receipt.bank_reference(reference) do
      nil -> nil
      reference -> booked_on_reference(receipt, reference)
    end
  end

  defp booked_on_reference(receipt, reference) do
    Repo.one(
      from r in Receipt,
        join: t in Transaction,
        on: t.receipt_id == r.id,
        where:
          r.user_id == ^receipt.user_id and r.id != ^receipt.id and r.status == :booked and
            r.bank_reference == ^reference,
        select: min(t.date_time)
    )
    |> then(&(&1 && NaiveDateTime.to_date(&1)))
  end

  defp model, do: config(:model)
  defp paperless, do: config(:paperless)
  defp text_extractor, do: config(:text_extractor)
  defp config(key), do: Application.fetch_env!(:abakus, __MODULE__)[key]
end

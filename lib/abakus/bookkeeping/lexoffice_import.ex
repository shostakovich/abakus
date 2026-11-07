defmodule Abakus.Bookkeeping.LexofficeImport do
  @moduledoc """
  The one-off import from Lexoffice (`Abakus.Bookkeeping.Lexoffice`): its customers, the invoices written there,
  each with its original PDF, which goes to the user's Paperless like an uploaded receipt, and whether Lexoffice saw
  it paid or voided, and the receipts with their items, payments and files, which go to Paperless the same way and
  are then matched to the business transactions (`Abakus.Bookkeeping.LexofficeReceipts`). Last, the returns the
  owner names as filed are locked (`Abakus.Bookkeeping.Filings.lock_filed_elsewhere/2`), from the first year of what
  came from Lexoffice on: the Voranmeldungen up to the last quarter filed, and the Umsatzsteuererklärung and EÜR with
  the year's Voranmeldungen up to the last year filed. What came over before is skipped by its Lexoffice id, so a
  second run duplicates nothing and asks Lexoffice only for what is new; drafts and voided receipts stay behind. A
  user's imports run one at a time.

  A contact with the customer role becomes a customer, or is linked to the customer of the same name the owner made
  before; Abakus keeps no vendors. An invoice whose contact is no customer here goes to the customer of the same
  name, or to a new one with the invoice's address. One Abakus cannot take over as it is, such as one with several
  VAT rates, is skipped and reported, as is one Lexoffice or Paperless fails on, such as a file not found or not
  taken; a refused key, being slowed down, a timeout or an unreachable server stop the import, and running it again
  goes on from there.
  """

  import Ecto.Query
  import Abakus.Owned

  alias Abakus.Bookkeeping.{
    Customer,
    Filings,
    Invoice,
    Lexoffice,
    LexofficeReceipt,
    LexofficeReceipts
  }

  alias Abakus.Bookkeeping.Lexoffice.Records
  alias Abakus.{Ids, Paperless, Repo}
  alias Abakus.Users.Scope

  @page_size 250
  @number_taken "Die Rechnungsnummer gibt es in Abakus schon"
  @incomplete "Die Rechnung ist unvollständig"
  @no_recipient "Die Rechnung hat keinen Empfänger"

  @typedoc """
  How far the import is: the customers taken over, then each invoice done of all new ones, then each receipt.
  """
  @type progress ::
          {:customers, non_neg_integer}
          | {:invoices, done :: non_neg_integer, total :: non_neg_integer}
          | {:receipts, done :: non_neg_integer, total :: non_neg_integer}

  @typedoc """
  What the import brought: the new customers, invoices and receipts, the receipts it attached to their transactions
  and those waiting for review, the invoices and receipts skipped by number and why, and the periods it locked.
  """
  @type result :: %{
          customers: non_neg_integer,
          invoices: non_neg_integer,
          receipts: non_neg_integer,
          matched: non_neg_integer,
          review: non_neg_integer,
          skipped: [{number :: String.t() | nil, reason :: String.t()}],
          locked: [Filings.period()]
        }

  @doc """
  Takes over what is new in Lexoffice with the API `key`. Options: `:quarter_filed`, the last quarter whose
  Voranmeldung was filed as `{year, quarter}`, and `:year_filed`, the last year whose Umsatzsteuererklärung and EÜR
  were filed, each nil for none, and `:progress`, told how far it is. `{:error, :running}` while another import of
  the user runs, `{:error, :not_connected}` without Paperless, else Lexoffice's or Paperless's error.
  """
  @spec run(Scope.t(), Lexoffice.key(), keyword) :: {:ok, result} | {:error, term}
  def run(%Scope{} = scope, key, opts \\ []) do
    lock = {{__MODULE__, user_id(scope)}, self()}

    if :global.set_lock(lock, [node()], 0) do
      try do
        import_all(scope, key, opts)
      after
        :global.del_lock(lock, [node()])
      end
    else
      {:error, :running}
    end
  end

  defp import_all(scope, key, opts) do
    progress = Keyword.get(opts, :progress, fn _progress -> :ok end)

    with {:ok, connection} <- Paperless.connection(scope),
         {:ok, contacts} <- all(key, "contacts", []),
         customers = import_customers(scope, contacts),
         _progress = progress.({:customers, customers}),
         {:ok, vouchers} <-
           all(key, "voucherlist", voucherType: voucher_types(), voucherStatus: "any"),
         {invoices, receipts} = Enum.split_with(vouchers, &(&1["voucherType"] == "invoice")),
         {:ok, invoices, skipped} <-
           import_each(new_invoices(scope, invoices), :invoices, progress, fn voucher ->
             import_invoice(scope, key, connection, voucher)
           end),
         names = Map.new(contacts, &{&1["id"], Records.name(&1)}),
         {:ok, receipts, skipped_receipts} <-
           import_each(new_receipts(scope, receipts), :receipts, progress, fn voucher ->
             import_receipt(scope, key, connection, voucher, names)
           end) do
      matched = LexofficeReceipts.match(scope)

      {:ok,
       %{
         customers: customers,
         invoices: invoices,
         receipts: receipts,
         matched: matched,
         review: LexofficeReceipts.review_count(scope),
         skipped: skipped ++ skipped_receipts,
         locked: lock_filed(scope, opts[:quarter_filed], opts[:year_filed])
       }}
    end
  end

  defp voucher_types, do: Enum.join(["invoice" | Records.receipt_types()], ",")

  defp all(key, path, params, page \\ 0, found \\ []) do
    case Lexoffice.client().get(key, [path], params ++ [page: page, size: @page_size]) do
      {:ok, %{"content" => [_ | _] = content, "last" => false}} ->
        all(key, path, params, page + 1, found ++ content)

      {:ok, %{"content" => content}} when is_list(content) ->
        {:ok, found ++ content}

      {:ok, _other} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_customers(scope, contacts) do
    known = MapSet.new(Repo.all(from c in owned(Customer, scope), select: c.lexoffice_id))

    contacts
    |> Enum.filter(&(Records.customer?(&1) and &1["id"] not in known))
    |> Enum.count(&match?({:ok, _customer}, take_customer(scope, Records.customer(&1))))
  end

  defp take_customer(scope, attrs) do
    case attrs.name && named(scope, attrs.name, unlinked: true) do
      %Customer{} = customer ->
        customer |> Ecto.Changeset.change(lexoffice_id: attrs.lexoffice_id) |> Repo.update()

      _none ->
        insert_customer(scope, attrs)
    end
  end

  defp insert_customer(scope, attrs),
    do: %Customer{user_id: user_id(scope)} |> Customer.import_changeset(attrs) |> Repo.insert()

  defp new_invoices(scope, vouchers) do
    known = MapSet.new(Repo.all(from i in owned(Invoice, scope), select: i.lexoffice_id))
    Enum.filter(vouchers, &(&1["voucherStatus"] != "draft" and &1["id"] not in known))
  end

  defp import_each(vouchers, kind, progress, import) do
    total = length(vouchers)
    progress.({kind, 0, total})

    vouchers
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, 0, []}, fn {voucher, done}, {:ok, imported, skipped} ->
      result = outcome(import.(voucher))
      progress.({kind, done, total})

      case result do
        :ok ->
          {:cont, {:ok, imported + 1, skipped}}

        {:skip, reason} ->
          {:cont, {:ok, imported, skipped ++ [{voucher["voucherNumber"], reason}]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp outcome({:ok, _record}), do: :ok
  defp outcome({:skip, reason}), do: {:skip, reason}

  defp outcome({:error, reason}),
    do: if(stops?(reason), do: {:error, reason}, else: {:skip, failed(reason)})

  defp stops?(reason) when reason in [:unauthorized, :rate_limited, :timeout, :unreachable],
    do: true

  # Paperless refusing its token or too slow to consume would fail every voucher alike.
  defp stops?(:consuming), do: true
  defp stops?({:http_status, status}) when status in [401, 403], do: true
  defp stops?(_reason), do: false

  defp failed(:not_found), do: "In Lexoffice nicht gefunden"
  defp failed(:not_consumed), do: "Paperless nimmt die Datei nicht an"
  defp failed(:too_large), do: "Die Datei ist zu groß"
  defp failed({:http_status, status}), do: "Lexoffice oder Paperless meldet Fehler #{status}"
  defp failed(_reason), do: "Lexoffice oder Paperless meldet einen Fehler"

  defp import_invoice(scope, key, connection, %{"id" => id}) do
    with {:ok, json} <- Lexoffice.client().get(key, ["invoices", id], []),
         {:ok, attrs} <- read(json),
         {:ok, payments} <- invoice_payments(key, json),
         attrs = Map.merge(attrs, Records.status(json, payments)),
         {:ok, customer} <- customer(scope, attrs),
         :ok <- check_invoice(scope, attrs, customer),
         {:ok, pdf} <- pdf(key, json),
         {:ok, paperless_id} <-
           Paperless.client().upload(connection, pdf, "Rechnung #{attrs.number}.pdf") do
      insert_invoice(scope, Map.put(attrs, :paperless_id, paperless_id), customer)
    end
  end

  defp read(json) do
    case Records.invoice(json) do
      {:ok, attrs} -> {:ok, attrs}
      {:error, reason} -> {:skip, "Rechnung #{reason}"}
    end
  end

  defp invoice_payments(key, %{"id" => id, "voucherStatus" => status})
       when status in ["paid", "paidoff"],
       do: payments(key, id)

  defp invoice_payments(_key, _json), do: {:ok, nil}

  defp payments(key, id) do
    case Lexoffice.client().get(key, ["payments", id], []) do
      {:ok, payments} -> {:ok, payments}
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp pdf(key, json) do
    with {:ok, file_id} <- file_id(key, json), do: Lexoffice.client().download(key, file_id)
  end

  defp file_id(key, %{"id" => id} = json) do
    case get_in(json, ["files", "documentFileId"]) do
      file_id when is_binary(file_id) ->
        {:ok, file_id}

      _none ->
        case Lexoffice.client().get(key, ["invoices", id, "document"], []) do
          {:ok, %{"documentFileId" => file_id}} when is_binary(file_id) -> {:ok, file_id}
          {:ok, _other} -> {:error, :invalid_response}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp check_invoice(scope, attrs, customer) do
    cond do
      Repo.exists?(from i in owned(Invoice, scope), where: i.number == ^attrs.number) ->
        {:skip, @number_taken}

      not valid_invoice?(scope, attrs, customer) ->
        {:skip, @incomplete}

      true ->
        :ok
    end
  end

  defp valid_invoice?(scope, attrs, %Ecto.Changeset{} = new_customer) do
    customer = %{Ecto.Changeset.apply_changes(new_customer) | id: Ids.generate()}
    valid_invoice?(scope, attrs, customer)
  end

  defp valid_invoice?(scope, attrs, customer),
    do: invoice_changeset(scope, Map.put(attrs, :paperless_id, 0), customer).valid?

  defp insert_invoice(scope, attrs, customer) do
    Repo.transact(fn ->
      with {:ok, customer} <- insert_new(customer) do
        scope |> invoice_changeset(attrs, customer) |> Repo.insert() |> skip_invalid()
      end
    end)
    |> case do
      {:ok, invoice} -> {:ok, invoice}
      {:error, {:skip, reason}} -> {:skip, reason}
    end
  end

  defp invoice_changeset(scope, attrs, customer) do
    recipient = %{
      attrs.recipient
      | name: attrs.recipient.name || customer.name,
        vat_id: customer.vat_id
    }

    Invoice.import_changeset(
      %Invoice{user_id: user_id(scope)},
      Map.merge(attrs, %{recipient: recipient, customer_id: customer.id})
    )
  end

  defp insert_new(%Customer{} = customer), do: {:ok, customer}

  defp insert_new(%Ecto.Changeset{} = changeset) do
    case Repo.insert(changeset) do
      {:ok, customer} -> {:ok, customer}
      {:error, _changeset} -> {:error, {:skip, @no_recipient}}
    end
  end

  defp skip_invalid({:ok, invoice}), do: {:ok, invoice}

  defp skip_invalid({:error, %Ecto.Changeset{errors: errors}}) do
    if Keyword.has_key?(errors, :number),
      do: {:error, {:skip, @number_taken}},
      else: {:error, {:skip, @incomplete}}
  end

  defp customer(scope, %{contact_id: contact_id, recipient: recipient}) do
    case known_customer(scope, contact_id) || (recipient.name && named(scope, recipient.name)) do
      %Customer{} = customer -> {:ok, customer}
      _none -> new_customer(scope, contact_id, recipient)
    end
  end

  defp known_customer(_scope, nil), do: nil

  defp known_customer(scope, contact_id),
    do: Repo.one(from c in owned(Customer, scope), where: c.lexoffice_id == ^contact_id)

  defp new_customer(scope, contact_id, recipient) do
    attrs =
      recipient
      |> Map.take([:name, :street, :postal_code, :city, :country])
      |> Map.put(:lexoffice_id, contact_id)

    changeset = Customer.import_changeset(%Customer{user_id: user_id(scope)}, attrs)
    if changeset.valid?, do: {:ok, changeset}, else: {:skip, @no_recipient}
  end

  defp named(scope, name, opts \\ []) do
    query =
      from c in owned(Customer, scope),
        where: fragment("lower(?) = lower(?)", c.name, ^String.trim(name)),
        order_by: c.inserted_at,
        limit: 1

    if opts[:unlinked],
      do: Repo.one(where(query, [c], is_nil(c.lexoffice_id))),
      else: Repo.one(query)
  end

  defp new_receipts(scope, vouchers) do
    known = MapSet.new(Repo.all(from r in owned(LexofficeReceipt, scope), select: r.lexoffice_id))

    Enum.filter(
      vouchers,
      &(&1["voucherStatus"] not in ["draft", "voided"] and &1["id"] not in known)
    )
  end

  defp import_receipt(scope, key, connection, %{"id" => id}, names) do
    with {:ok, json} <- Lexoffice.client().get(key, ["vouchers", id], []),
         {:ok, payments} <- payments(key, id),
         {:ok, attrs} <- read_receipt(json, payments, names),
         {:ok, paperless_ids} <- file_receipt(key, connection, attrs) do
      %LexofficeReceipt{
        user_id: user_id(scope),
        lexoffice_id: attrs.lexoffice_id,
        number: attrs.number,
        date: attrs.date,
        contact: attrs.contact,
        total: attrs.total,
        items: attrs.items,
        payments: attrs.payments,
        paperless_ids: paperless_ids
      }
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :lexoffice_id])
    end
  end

  defp read_receipt(json, payments, names) do
    case Records.receipt(json, payments, names) do
      {:ok, attrs} -> {:ok, attrs}
      {:error, reason} -> {:skip, "Beleg #{reason}"}
    end
  end

  defp file_receipt(key, connection, attrs) do
    attrs.file_ids
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {file_id, index}, {:ok, ids} ->
      with {:ok, content} <- Lexoffice.client().download(key, file_id),
           filename = LexofficeReceipt.title(attrs, index) <> extension(content),
           {:ok, paperless_id} <- Paperless.client().upload(connection, content, filename) do
        {:cont, {:ok, ids ++ [paperless_id]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp extension(<<0x89, "PNG", _rest::binary>>), do: ".png"
  defp extension(<<0xFF, 0xD8, _rest::binary>>), do: ".jpg"
  defp extension(_pdf), do: ".pdf"

  defp lock_filed(scope, quarter_filed, year_filed) do
    case first_year(scope) do
      nil ->
        []

      first ->
        Filings.lock_filed_elsewhere(
          scope,
          Enum.uniq(quarters(first, quarter_filed) ++ years(first, year_filed))
        )
    end
  end

  defp quarters(_first, nil), do: []

  defp quarters(first, {year, quarter}) do
    for y <- first..year//1, q <- 1..4, {y, q} <= {year, quarter}, do: {:vat_quarter, y, q}
  end

  defp years(_first, nil), do: []

  defp years(first, year) do
    for y <- first..year//1,
        period <- [{:vat_year, y}, {:euer, y} | Enum.map(1..4, &{:vat_quarter, y, &1})],
        do: period
  end

  defp first_year(scope) do
    [
      Repo.one(from r in owned(LexofficeReceipt, scope), select: min(r.date)),
      Repo.one(
        from i in owned(Invoice, scope), where: not is_nil(i.lexoffice_id), select: min(i.date)
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(Date, fn -> nil end)
    |> then(&(&1 && &1.year))
  end
end

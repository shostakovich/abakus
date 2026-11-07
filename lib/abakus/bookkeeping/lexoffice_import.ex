defmodule Abakus.Bookkeeping.LexofficeImport do
  @moduledoc """
  The one-off import from Lexoffice (`Abakus.Bookkeeping.Lexoffice`): its customers and the invoices written there,
  each with its original PDF, which goes to the user's Paperless like an uploaded receipt, and whether Lexoffice saw
  it paid or voided. What came over before is skipped by its Lexoffice id, so a second run duplicates nothing and
  asks Lexoffice only for what is new; drafts stay behind.

  A contact becomes a customer, or is linked to the customer of the same name the owner made before. An invoice
  whose contact is no customer here goes to the customer of the same name, or to a new one with the invoice's
  address. One Abakus cannot take over as it is, such as one with several VAT rates, is skipped and
  reported; an error of Lexoffice or Paperless stops the import, and running it again goes on from there.
  """

  import Ecto.Query
  import Abakus.Owned

  alias Abakus.Bookkeeping.{Customer, Invoice, Lexoffice}
  alias Abakus.Bookkeeping.Lexoffice.Records
  alias Abakus.{Paperless, Repo}
  alias Abakus.Users.Scope

  @page_size 250

  @typedoc "How far the import is: the customers taken over, then each invoice done of all new ones."
  @type progress ::
          {:customers, non_neg_integer}
          | {:invoices, done :: non_neg_integer, total :: non_neg_integer}

  @typedoc "What the import brought: the new customers and invoices, and the invoices skipped by number and why."
  @type result :: %{
          customers: non_neg_integer,
          invoices: non_neg_integer,
          skipped: [{number :: String.t(), reason :: String.t()}]
        }

  @doc """
  Takes over what is new in Lexoffice with the API `key`, telling `progress` how far it is. `{:error,
  :not_connected}` without Paperless, else Lexoffice's or Paperless's error.
  """
  @spec run(Scope.t(), Lexoffice.key(), (progress -> any)) :: {:ok, result} | {:error, term}
  def run(%Scope{} = scope, key, progress \\ fn _progress -> :ok end) do
    with {:ok, connection} <- paperless(scope),
         {:ok, contacts} <- all(key, "contacts", customer: true),
         customers = import_customers(scope, contacts),
         _progress = progress.({:customers, customers}),
         {:ok, vouchers} <- all(key, "voucherlist", voucherType: "invoice", voucherStatus: "any"),
         {:ok, invoices, skipped} <-
           import_invoices(scope, key, connection, new_invoices(scope, vouchers), progress) do
      {:ok, %{customers: customers, invoices: invoices, skipped: skipped}}
    end
  end

  defp paperless(scope) do
    connection = Paperless.get_connection(scope)
    if Paperless.connected?(connection), do: {:ok, connection}, else: {:error, :not_connected}
  end

  defp all(key, path, params, page \\ 0, found \\ []) do
    case Lexoffice.client().get(key, path, params ++ [page: page, size: @page_size]) do
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

  defp import_invoices(scope, key, connection, vouchers, progress) do
    total = length(vouchers)
    progress.({:invoices, 0, total})

    vouchers
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, 0, []}, fn {voucher, done}, {:ok, imported, skipped} ->
      result = import_invoice(scope, key, connection, voucher)
      progress.({:invoices, done, total})

      case result do
        {:ok, _invoice} ->
          {:cont, {:ok, imported + 1, skipped}}

        {:skip, reason} ->
          {:cont, {:ok, imported, skipped ++ [{voucher["voucherNumber"], reason}]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp import_invoice(scope, key, connection, %{"id" => id}) do
    with {:ok, json} <- Lexoffice.client().get(key, "invoices/" <> segment(id), []),
         {:ok, attrs} <- read(json),
         {:ok, payments} <- payments(key, json),
         {:ok, pdf} <- pdf(key, json),
         {:ok, paperless_id} <-
           Paperless.client().upload(connection, pdf, "Rechnung #{attrs.number}.pdf") do
      attrs
      |> Map.merge(Records.status(json, payments))
      |> Map.put(:paperless_id, paperless_id)
      |> then(&insert_invoice(scope, &1))
    end
  end

  defp read(json) do
    case Records.invoice(json) do
      {:ok, attrs} -> {:ok, attrs}
      {:error, reason} -> {:skip, "Rechnung #{reason}"}
    end
  end

  defp payments(key, %{"id" => id, "voucherStatus" => status})
       when status in ["paid", "paidoff"] do
    case Lexoffice.client().get(key, "payments/" <> segment(id), []) do
      {:ok, payments} -> {:ok, payments}
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp payments(_key, _json), do: {:ok, nil}

  defp pdf(key, json) do
    with {:ok, file_id} <- file_id(key, json), do: Lexoffice.client().download(key, file_id)
  end

  defp file_id(key, %{"id" => id} = json) do
    case get_in(json, ["files", "documentFileId"]) do
      file_id when is_binary(file_id) ->
        {:ok, file_id}

      _none ->
        case Lexoffice.client().get(key, "invoices/#{segment(id)}/document", []) do
          {:ok, %{"documentFileId" => file_id}} when is_binary(file_id) -> {:ok, file_id}
          {:ok, _other} -> {:error, :invalid_response}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp insert_invoice(scope, attrs) do
    Repo.transact(fn ->
      with {:ok, customer} <- customer(scope, attrs) do
        recipient = %{
          attrs.recipient
          | name: attrs.recipient.name || customer.name,
            vat_id: customer.vat_id
        }

        %Invoice{user_id: user_id(scope)}
        |> Invoice.import_changeset(
          Map.merge(attrs, %{recipient: recipient, customer_id: customer.id})
        )
        |> Repo.insert()
        |> skip_invalid()
      end
    end)
    |> case do
      {:ok, invoice} -> {:ok, invoice}
      {:error, {:skip, reason}} -> {:skip, reason}
    end
  end

  defp skip_invalid({:ok, invoice}), do: {:ok, invoice}

  defp skip_invalid({:error, %Ecto.Changeset{errors: errors}}) do
    if Keyword.has_key?(errors, :number),
      do: {:error, {:skip, "Die Rechnungsnummer gibt es in Abakus schon"}},
      else: {:error, {:skip, "Die Rechnung ist unvollständig"}}
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

    case insert_customer(scope, attrs) do
      {:ok, customer} -> {:ok, customer}
      {:error, _changeset} -> {:error, {:skip, "Die Rechnung hat keinen Empfänger"}}
    end
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

  defp segment(id), do: URI.encode(id, &URI.char_unreserved?/1)
end

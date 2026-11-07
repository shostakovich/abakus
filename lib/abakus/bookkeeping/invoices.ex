defmodule Abakus.Bookkeeping.Invoices do
  @moduledoc """
  The user's customers and the invoices they write to them, from the sender of the bookkeeping settings
  (`Abakus.Bookkeeping.Settings`).

  Writing an invoice gives it the next number: the year of its date followed by a counter one above the user's
  highest, so the counter runs on across years and continues what the Lexoffice import brought. It also fixes the
  due date by the settings' payment days and keeps the sender and the customer as they are, so that the written
  invoice stays as it was. Reverse charge needs the sender's VAT id and a customer in another EU country with its
  VAT id.
  """

  import Ecto.Changeset
  import Ecto.Query
  import Abakus.Owned

  alias Abakus.Bookkeeping.{Countries, Customer, Invoice, Party, Position, Settings}
  alias Abakus.{Ids, Repo}
  alias Abakus.Users.Scope

  @doc "The user's customers by name."
  def list_customers(%Scope{} = scope),
    do:
      Repo.all(
        from c in owned(Customer, scope), order_by: [fragment("? COLLATE NOCASE", c.name), c.id]
      )

  def get_customer(%Scope{} = scope, id) do
    case Ids.cast(id) do
      {:ok, id} -> Repo.one(from c in owned(Customer, scope), where: c.id == ^id)
      :error -> nil
    end
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}),
    do: Customer.changeset(customer, attrs)

  def create_customer(%Scope{} = scope, attrs),
    do: %Customer{user_id: user_id(scope)} |> Customer.changeset(attrs) |> Repo.insert()

  def update_customer(%Scope{} = scope, %Customer{} = customer, attrs),
    do: own!(scope, customer) |> Customer.changeset(attrs) |> Repo.update()

  @doc "The user's invoices, the latest number first."
  def list_invoices(%Scope{} = scope),
    do: Repo.all(from i in owned(Invoice, scope), order_by: [desc: i.counter, desc: i.id])

  def get_invoice(%Scope{} = scope, id) do
    case Ids.cast(id) do
      {:ok, id} -> Repo.one(from i in owned(Invoice, scope), where: i.id == ^id)
      :error -> nil
    end
  end

  @doc "A new invoice dated `today` for the month before, with one position in hours."
  def new_invoice(%Date{} = today) do
    last_month = today |> Date.beginning_of_month() |> Date.add(-1)

    %Invoice{
      date: today,
      service_from: Date.beginning_of_month(last_month),
      service_to: last_month,
      vat: :rate_19,
      positions: [%Position{unit: "HUR"}]
    }
  end

  def change_invoice(%Invoice{} = invoice, attrs \\ %{}), do: Invoice.changeset(invoice, attrs)

  @doc """
  Writes an invoice from `attrs` with the next number. `{:error, :no_sender}` while the settings lack the sender,
  `{:error, changeset}` for invalid attrs.
  """
  def write_invoice(%Scope{} = scope, attrs) do
    settings = Settings.get_settings(scope)

    if Settings.complete?(settings) do
      %Invoice{user_id: user_id(scope)}
      |> Invoice.changeset(attrs)
      |> put_parties(scope, settings)
      |> insert_numbered(scope, settings)
    else
      {:error, :no_sender}
    end
  end

  defp put_parties(changeset, scope, settings) do
    id = get_field(changeset, :customer_id)

    case id && get_customer(scope, id) do
      nil when is_nil(id) ->
        changeset

      nil ->
        add_error(changeset, :customer_id, "nicht gefunden")

      customer ->
        put_customer(changeset, customer, settings)
    end
  end

  defp put_customer(changeset, customer, settings) do
    if Enum.any?([customer.street, customer.postal_code, customer.city], &blank?/1) do
      add_error(changeset, :customer_id, "Der Kunde braucht eine vollständige Anschrift.")
    else
      changeset
      |> put_embed(:sender, Party.sender(settings))
      |> put_embed(:recipient, Party.recipient(customer))
      |> validate_reverse_charge(customer, settings)
    end
  end

  defp validate_reverse_charge(changeset, customer, settings) do
    cond do
      get_field(changeset, :vat) != :reverse_charge ->
        changeset

      blank?(settings.vat_id) ->
        add_error(changeset, :vat, "braucht deine USt-IdNr. in den Einstellungen")

      not Countries.other_eu?(customer.country) or blank?(customer.vat_id) ->
        add_error(changeset, :vat, "nur für Kunden im EU-Ausland mit USt-IdNr.")

      true ->
        changeset
    end
  end

  defp insert_numbered(%{valid?: false} = changeset, _scope, _settings),
    do: {:error, Map.put(changeset, :action, :insert)}

  defp insert_numbered(changeset, scope, settings) do
    Repo.transact(fn ->
      counter = next_counter(scope)
      date = get_field(changeset, :date)

      changeset
      |> change(
        counter: counter,
        number: Invoice.number(date.year, counter),
        due_date: Date.add(date, settings.payment_days)
      )
      |> unique_constraint(:number, name: :bookkeeping_invoices_user_id_number_index)
      |> Repo.insert()
    end)
  end

  defp next_counter(scope) do
    case Repo.one(from i in owned(Invoice, scope), select: max(i.counter)) do
      nil -> 1
      counter -> counter + 1
    end
  end

  defp blank?(value), do: value in [nil, ""]
end

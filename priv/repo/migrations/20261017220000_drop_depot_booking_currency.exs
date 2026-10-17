defmodule Abakus.Repo.Migrations.DropDepotBookingCurrency do
  use Ecto.Migration

  @foreign [
    {"Depot accounts", "SELECT count(*) FROM depot_accounts WHERE currency != 'EUR'"},
    {"Depot transactions", "SELECT count(*) FROM depot_transactions WHERE currency != 'EUR'"},
    {"Depot transaction units",
     "SELECT count(*) FROM depot_transaction_units WHERE currency != 'EUR' OR fx_currency IS NOT NULL OR type = 'gross_value'"}
  ]

  def up do
    refuse_foreign_bookings!()

    alter table(:depot_accounts) do
      remove :currency
    end

    alter table(:depot_transactions) do
      remove :currency
    end

    alter table(:depot_transaction_units) do
      remove :currency
      remove :fx_amount
      remove :fx_currency
      remove :fx_rate
    end
  end

  def down,
    do: raise(Ecto.MigrationError, "dropping the Depot's booking currency is irreversible")

  defp refuse_foreign_bookings! do
    found =
      for {label, sql} <- @foreign,
          [[count]] = repo().query!(sql, [], log: false).rows,
          count > 0,
          do: "#{count} #{label}"

    if found != [],
      do:
        raise(
          "The Depot books in euros only, but #{Enum.join(found, ", ")} hold another currency " <>
            "or a gross value unit: correct or delete them first"
        )
  end
end

defmodule Abakus.Depot.Portfolios.PortfolioForm do
  @moduledoc "A new portfolio as the user enters it: its name and the name of its new Verrechnungskonto."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :account_name, :string, default: "Verrechnungskonto"
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:name, :account_name])
    |> update_change(:name, &String.trim/1)
    |> update_change(:account_name, &String.trim/1)
    |> validate_required([:name, :account_name])
    |> validate_length(:name, max: 100)
    |> validate_length(:account_name, max: 100)
  end
end

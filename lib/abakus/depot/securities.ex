defmodule Abakus.Depot.Securities do
  @moduledoc """
  Securities, their prices, compositions, DivvyDiary dividends and attribute types. They are
  shared by all users, so every signed-in user may read and change them; the scope only says who
  is asking.
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Abakus.Depot.Allocation
  alias Abakus.Depot.Securities.{AttributeType, Composition, DivvyDiaryDividend, Price, Security}
  alias Abakus.Repo
  alias Abakus.Users.Scope

  def list_securities(%Scope{}),
    do: Repo.all(from s in Security, order_by: [s.retired, fragment("? COLLATE NOCASE", s.name)])

  @doc "The security with `id`, nil for an unknown one."
  def get_security(%Scope{}, id), do: Repo.get(Security, id)

  @doc "A form for a security created by its ISIN, see `create_security/2`."
  def change_new_security(attrs \\ %{}),
    do: %Security{} |> Security.create_changeset(attrs) |> validate_new_isin()

  @doc """
  Creates a security by its ISIN with a name and, for prices from Yahoo, a symbol. It belongs to
  no PP file. An ISIN that a security already has is refused, the user picks that one instead.
  """
  def create_security(%Scope{}, attrs), do: attrs |> change_new_security() |> Repo.insert()

  defp validate_new_isin(changeset) do
    with [] <- Keyword.get_values(changeset.errors, :isin),
         isin when is_binary(isin) <- get_field(changeset, :isin),
         %Security{name: name} <- Repo.one(from s in Security, where: s.isin == ^isin, limit: 1) do
      add_error(changeset, :isin, "gehört schon zu %{name}", name: name)
    else
      _new -> changeset
    end
  end

  def list_prices(%Scope{}, %Security{id: id}),
    do: Repo.all(from p in Price, where: p.security_id == ^id, order_by: p.date)

  @doc "The securities whose prices come from Yahoo, without retired ones."
  def list_yahoo_securities do
    Repo.all(
      from s in Security, where: s.quote_feed == :yahoo and not s.retired, order_by: s.name
    )
  end

  @doc """
  Claims the Yahoo securities not checked since `cutoff` by marking them checked at `now`, in one
  statement, so that pages opened at the same time fetch each quote once.
  """
  def claim_unchecked_yahoo_securities(cutoff, now) do
    unchecked =
      from s in Security,
        where: s.quote_feed == :yahoo and not s.retired,
        where: is_nil(s.checked_at) or s.checked_at < ^cutoff

    # Only a write waits for another, such as an import, so pages read first.
    if Repo.exists?(unchecked) do
      {_count, securities} =
        Repo.update_all(select(unchecked, [s], s), set: [checked_at: now])

      securities
    else
      []
    end
  end

  ## Securities from Yahoo

  @doc """
  A form for creating a security from a Yahoo symbol such as `IUSQ.DE`, in capitals and without
  spaces around it.
  """
  def change_yahoo_symbol(attrs \\ %{}) do
    {%{}, %{symbol: :string}}
    |> cast(attrs, [:symbol])
    |> update_change(:symbol, &(&1 |> String.trim() |> String.upcase()))
    |> validate_required([:symbol], message: "braucht ein Symbol")
    |> validate_format(:symbol, ~r/^[A-Z0-9^][A-Z0-9.^=-]*$/, message: "ist kein Yahoo-Symbol")
    |> validate_length(:symbol, max: 32)
  end

  @doc "The security that takes its prices from the Yahoo `symbol`, nil for none."
  def get_yahoo_security(symbol) do
    Repo.one(
      from s in Security,
        where: s.quote_feed == :yahoo and not s.retired,
        where: fragment("upper(?)", s.symbol) == ^String.upcase(symbol),
        order_by: s.id,
        limit: 1
    )
  end

  @doc """
  Creates a security from the Yahoo `symbol` with the name, currency and prices of `chart`, as
  `PriceFeed` delivers it at `now`. It belongs to no PP file, so an import leaves it alone. The
  security another request created meanwhile is returned as it is.
  """
  def create_yahoo_security(%Scope{}, symbol, chart, now) do
    Repo.transact(fn ->
      case get_yahoo_security(symbol) do
        nil -> {:ok, insert_yahoo_security(symbol, chart, now)}
        security -> {:ok, security}
      end
    end)
  end

  defp insert_yahoo_security(symbol, chart, now) do
    security =
      Repo.insert!(%Security{
        name: chart.name || symbol,
        currency: chart.currency,
        quote_feed: :yahoo,
        symbol: symbol,
        quote_feed_set_by_user: true
      })

    store_yahoo_prices(security, chart.closes)
    record_quote(security, chart.quote, now)
  end

  @doc """
  Sets where prices come from; a later PP import keeps this choice. A switch to Yahoo or a new
  Yahoo symbol drops the Yahoo prices and the quote of the old one, a switch to manual keeps them.
  """
  def update_quote_feed(%Scope{}, %Security{} = security, attrs) do
    changeset = Security.quote_feed_changeset(security, attrs)
    new_source? = changed?(changeset, :quote_feed) or changed?(changeset, :symbol)

    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(changeset) do
        {:ok, maybe_drop_yahoo_prices(updated, new_source?)}
      end
    end)
  end

  defp maybe_drop_yahoo_prices(%Security{quote_feed: :yahoo} = security, true = _new_source) do
    Repo.delete_all(from p in Price, where: p.security_id == ^security.id and p.source == :yahoo)

    security
    |> change(latest_at: nil, latest_date: nil, latest_close: nil)
    |> change(fetched_at: nil, checked_at: nil, fetch_error: nil)
    |> Repo.update!()
  end

  defp maybe_drop_yahoo_prices(security, _new_source), do: security

  @doc """
  Calls `fun` with the current security if it still takes its prices from the Yahoo symbol of
  `security`, so a fetch never stores what an old symbol delivered; returns `:skipped` otherwise.
  """
  def with_same_yahoo_symbol(%Security{id: id, symbol: symbol}, fun) do
    {:ok, result} =
      Repo.transact(fn ->
        case Repo.get(Security, id) do
          %Security{quote_feed: :yahoo, retired: false, symbol: ^symbol} = current ->
            {:ok, fun.(current)}

          _changed ->
            {:ok, :skipped}
        end
      end)

    result
  end

  def list_securities_by_id(ids), do: Repo.all(from s in Security, where: s.id in ^ids)

  @doc """
  The closes of the securities as `{security_id, date, close}` from the last one on or before
  `date` on, so that every day from `date` on finds its price; all of them when none is that old.
  """
  def list_closes_since(security_ids, date) do
    last_on_or_before =
      from q in Price,
        where: q.security_id == parent_as(:security).id and q.date <= ^date,
        select: max(q.date)

    # Per security a range of the index on security and date, instead of a check of every close.
    Repo.all(
      from s in Security,
        as: :security,
        join: p in Price,
        on: p.security_id == s.id,
        where: s.id in ^security_ids,
        where: p.date >= coalesce(subquery(last_on_or_before), ^~D[0001-01-01]),
        select: {p.security_id, p.date, p.close}
    )
  end

  def last_price_date(%Security{id: id}),
    do: Repo.one(from p in Price, where: p.security_id == ^id, select: max(p.date))

  @doc "Stores `{date, close}` from Yahoo; days with a price from another source keep it."
  def store_yahoo_prices(%Security{id: id}, closes) do
    # The source check sits in the upsert itself, so a price an import stores meanwhile wins.
    only_over_yahoo =
      from p in Price,
        where: p.source == :yahoo,
        update: [set: [close: fragment("EXCLUDED.close")]]

    closes
    |> Enum.map(fn {date, close} ->
      %{security_id: id, date: date, close: close, source: :yahoo}
    end)
    |> Enum.chunk_every(5000)
    |> Enum.each(
      &Repo.insert_all(Price, &1,
        on_conflict: only_over_yahoo,
        conflict_target: [:security_id, :date]
      )
    )
  end

  @doc "Records a successful fetch with the latest quote."
  def record_quote(%Security{} = security, quote, now) do
    security
    |> change(
      latest_at: quote.at,
      latest_date: quote.date,
      latest_close: quote.close,
      fetched_at: now,
      checked_at: now,
      fetch_error: nil
    )
    |> Repo.update!()
  end

  def record_fetch_error(%Security{} = security, message, now),
    do: security |> change(fetch_error: message, checked_at: now) |> Repo.update!()

  ## Compositions

  @doc "The securities DivvyDiary may know: those with an ISIN, without retired ones."
  def list_securities_with_isin do
    Repo.all(
      from s in Security,
        where: not is_nil(s.isin) and s.isin != "" and not s.retired,
        order_by: s.name
    )
  end

  @doc "Stores the composition of a security, fetched at `now`, in place of the one before."
  def replace_composition(%Security{id: id}, %{countries: countries, sectors: sectors}, now) do
    Repo.insert!(
      %Composition{security_id: id, countries: countries, sectors: sectors, fetched_at: now},
      on_conflict: {:replace, [:countries, :sectors, :fetched_at]},
      conflict_target: :security_id
    )
  end

  @doc "The compositions of the securities with `ids` as `%{security_id => composition}`."
  def list_compositions(ids) do
    from(c in Composition, where: c.security_id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.security_id, &1})
  end

  ## DivvyDiary dividends

  @doc "Stores the dividends of a security, fetched at `now`, in place of those before."
  def replace_dividends(%Security{id: id}, dividends, now) do
    rows =
      for dividend <- dividends do
        dividend
        |> Map.take([:ex_date, :pay_date, :per_share, :currency])
        |> Map.merge(%{security_id: id, fetched_at: now})
      end

    Repo.transact(fn ->
      Repo.delete_all(from d in DivvyDiaryDividend, where: d.security_id == ^id)
      {count, _rows} = Repo.insert_all(DivvyDiaryDividend, rows)
      {:ok, count}
    end)
  end

  @doc "The DivvyDiary dividends of the securities with `ids`, by pay date."
  def list_divvy_diary_dividends(ids) do
    Repo.all(
      from d in DivvyDiaryDividend,
        where: d.security_id in ^ids,
        order_by: [d.pay_date, d.security_id]
    )
  end

  ## Profile

  @attributes_of_securities "name.abuchen.portfolio.model.Security"

  @doc """
  The profile of `security`:

  - `ter` and `fund_size`, see `Security.ter/1` and `Security.fund_size/1`
  - `attributes`: every other attribute set on it with its type, see `Security.attributes/2`
  - `composition`: its regions and sectors, see `Allocation.of_composition/1`; nil without one
  """
  def profile(%Scope{}, %Security{} = security) do
    types =
      Repo.all(
        from t in AttributeType, where: t.target == @attributes_of_securities, order_by: t.id
      )

    composition = Repo.get_by(Composition, security_id: security.id)

    %{
      ter: Security.ter(security),
      fund_size: Security.fund_size(security),
      attributes: Security.attributes(security, types),
      composition: composition && Allocation.of_composition(composition)
    }
  end
end

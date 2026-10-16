defmodule Abakus.Depot.PPImport do
  @moduledoc """
  Imports a Portfolio Performance file for a user, repeatably. Objects
  are matched by their PP UUID and updated in place, objects missing from the file are deleted,
  data entered in the Depot stays. Runs in one database transaction and returns how many
  objects of each kind were created, updated and deleted.
  """

  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]

  alias Abakus.Depot.Portfolios.{Account, Portfolio, SavingsPlan, Transaction, TransactionUnit}
  alias Abakus.Depot.PPImport.Reader
  alias Abakus.Depot.Securities.{AttributeType, PPSecurityLink, Price, Security}
  alias Abakus.Depot.Settings.Setting
  alias Abakus.Depot.Taxonomies.{Assignment, Classification, Taxonomy}
  alias Abakus.Repo
  alias Abakus.Users.Scope

  @kinds [
    :securities,
    :prices,
    :attribute_types,
    :accounts,
    :portfolios,
    :transactions,
    :savings_plans,
    :taxonomies,
    :classifications,
    :assignments
  ]

  # PP's own feed already uses Yahoo's exchange suffixes, e.g. LDGL.DE.
  @yahoo_feeds ["YAHOO", "YAHOO-ADJUSTEDCLOSE", "PP"]

  @doc "Reads the file at `path` and imports it for the scope's user."
  def run(%Scope{} = scope, path) do
    with {:ok, client} <- Reader.read(path), do: import_client(scope, client)
  end

  @doc "Imports a file already parsed by `Abakus.Depot.PPImport.Reader`."
  def import_client(%Scope{user: user}, client) do
    # A large file takes longer than the default 15 s checkout timeout.
    Repo.transact(fn -> {:ok, do_import(user.id, client)} end, timeout: :timer.minutes(5))
  end

  defp do_import(user_id, client) do
    empty = %{created: 0, updated: 0, deleted: 0}

    %{user_id: user_id, summary: Map.new(@kinds, &{&1, empty})}
    |> import_attribute_types(client)
    |> import_securities(client)
    |> import_prices(client)
    |> import_accounts(client)
    |> import_portfolios(client)
    |> import_transactions(client)
    |> import_savings_plans(client)
    |> import_taxonomies(client)
    |> delete_stale_holdings()
    |> Map.fetch!(:summary)
  end

  ## Securities

  defp import_attribute_types(ctx, client) do
    existing = Map.new(Repo.all(AttributeType), &{{&1.pp_id, &1.target}, &1})

    incoming =
      for t <- (client.settings && client.settings.attribute_types) || [] do
        attrs = Map.take(t, [:name, :column_label, :target, :value_type, :converter])
        {{t.id, t.target}, Map.put(attrs, :pp_id, t.id)}
      end

    # Shared by all users, so types missing from this file stay.
    incoming = Enum.uniq_by(incoming, &elem(&1, 0))
    {ctx, _ids} = upsert(ctx, :attribute_types, existing, incoming, AttributeType)
    ctx
  end

  defp import_securities(ctx, client) do
    links =
      Repo.all(from l in PPSecurityLink, where: l.user_id == ^ctx.user_id, preload: :security)
      |> Map.new(&{&1.pp_uuid, &1})

    file_uuids = MapSet.new(client.securities, & &1.uuid)

    # A security recreated in PP keeps its ISIN but gets a new UUID; its old link moves over.
    movable =
      for {uuid, link} <- links,
          not MapSet.member?(file_uuids, uuid),
          link.security.isin not in [nil, ""],
          into: %{},
          do: {link.security.isin, link}

    {ctx, ids, unmoved} =
      Enum.reduce(client.securities, {ctx, %{}, movable}, fn s, {ctx, ids, movable} ->
        attrs = security_attrs(s, client.base_currency)

        {{ctx, security}, movable} =
          case {links[s.uuid], movable[attrs.isin]} do
            {%{security: security}, _} ->
              {update_security(ctx, security, attrs), movable}

            {nil, %PPSecurityLink{} = link} ->
              Repo.update!(change(link, pp_uuid: s.uuid))
              {update_security(ctx, link.security, attrs), Map.delete(movable, attrs.isin)}

            {nil, nil} ->
              {link_security(ctx, s.uuid, attrs), movable}
          end

        {ctx, Map.put(ids, s.uuid, security.id), movable}
      end)

    moved = MapSet.new(Map.values(movable) -- Map.values(unmoved), & &1.id)

    stale_links =
      for {uuid, link} <- links,
          not MapSet.member?(file_uuids, uuid),
          not MapSet.member?(moved, link.id),
          do: link

    Map.merge(ctx, %{securities: ids, stale_links: stale_links})
  end

  defp link_security(ctx, uuid, attrs) do
    {ctx, security} =
      case unlinked_security(ctx.user_id, attrs.isin) do
        nil -> put_record(ctx, :securities, Security, nil, attrs)
        security -> update_security(ctx, security, attrs)
      end

    Repo.insert!(%PPSecurityLink{user_id: ctx.user_id, security_id: security.id, pp_uuid: uuid})
    {ctx, security}
  end

  # Another user's import may have created the security already; one created in the Depot
  # belongs to no PP file.
  defp unlinked_security(_user_id, isin) when isin in [nil, ""], do: nil

  defp unlinked_security(user_id, isin) do
    linked = from l in PPSecurityLink, where: l.user_id == ^user_id, select: l.security_id

    Repo.one(
      from s in Security,
        where: s.isin == ^isin and s.source == :pp_import and s.id not in subquery(linked),
        limit: 1
    )
  end

  defp update_security(ctx, security, attrs) do
    attrs = attrs |> keep_user_feed(security) |> keep_fetched_quote(security)
    update(ctx, :securities, security, attrs)
  end

  defp keep_user_feed(attrs, %Security{quote_feed_set_by_user: true}),
    do: Map.drop(attrs, [:quote_feed, :symbol])

  defp keep_user_feed(attrs, _security), do: attrs

  # A quote fetched since PP's stays; PP's own latest quote has no time of day.
  defp keep_fetched_quote(attrs, %Security{latest_at: nil}), do: attrs

  defp keep_fetched_quote(attrs, security) do
    if attrs.latest_date && Date.after?(attrs.latest_date, security.latest_date),
      do: Map.put(attrs, :latest_at, nil),
      else: Map.drop(attrs, [:latest_date, :latest_close])
  end

  defp security_attrs(s, base_currency) do
    {quote_feed, symbol} =
      if s.feed in @yahoo_feeds and s.ticker not in [nil, ""],
        do: {:yahoo, s.ticker},
        else: {:manual, nil}

    s
    |> Map.take([:name, :isin, :wkn, :note, :retired, :attributes])
    |> Map.merge(%{
      currency: s.currency || base_currency,
      pp_feed: s.feed,
      pp_ticker: s.ticker,
      quote_feed: quote_feed,
      symbol: symbol,
      latest_date: s.latest && s.latest.date,
      latest_close: s.latest && s.latest.close
    })
  end

  # PP's prices replace the PP prices stored so far and win over fetched ones on the same day.
  defp import_prices(ctx, client) do
    Enum.reduce(client.securities, ctx, fn s, ctx ->
      sync_prices(ctx, ctx.securities[s.uuid], Map.new(s.prices, &{&1.date, &1.close}))
    end)
  end

  defp sync_prices(ctx, security_id, incoming) do
    existing =
      Repo.all(
        from p in Price,
          where: p.security_id == ^security_id,
          select: {p.date, {p.id, p.close, p.source}}
      )
      |> Map.new()

    {new, changed} =
      incoming
      |> Enum.reject(fn {date, close} -> match?({_id, ^close, :pp}, existing[date]) end)
      |> Enum.split_with(fn {date, _close} -> is_nil(existing[date]) end)

    stale =
      for {date, {id, _close, :pp}} <- existing, not Map.has_key?(incoming, date), do: id

    (new ++ changed)
    |> Enum.map(fn {date, close} ->
      %{security_id: security_id, date: date, close: close, source: :pp}
    end)
    |> Enum.chunk_every(5000)
    |> Enum.each(
      &Repo.insert_all(Price, &1,
        on_conflict: {:replace, [:close, :source]},
        conflict_target: [:security_id, :date]
      )
    )

    stale
    |> Enum.chunk_every(5000)
    |> Enum.each(&Repo.delete_all(from p in Price, where: p.id in ^&1))

    ctx
    |> count(:prices, :created, length(new))
    |> count(:prices, :updated, length(changed))
    |> count(:prices, :deleted, length(stale))
  end

  ## Portfolios and accounts

  defp import_accounts(ctx, client) do
    existing = owned(Account, ctx.user_id)

    incoming =
      for a <- client.accounts do
        attrs = Map.take(a, [:name, :currency, :note, :retired, :attributes])
        {a.uuid, Map.merge(attrs, %{user_id: ctx.user_id, pp_uuid: a.uuid})}
      end

    {ctx, ids} = upsert(ctx, :accounts, existing, incoming, Account)
    Map.merge(ctx, %{accounts: ids, stale_accounts: stale(existing, ids)})
  end

  defp import_portfolios(ctx, client) do
    existing = owned(Portfolio, ctx.user_id)

    incoming =
      for p <- client.portfolios do
        attrs = Map.take(p, [:name, :note, :retired, :attributes])

        {p.uuid,
         Map.merge(attrs, %{
           user_id: ctx.user_id,
           reference_account_id: ctx.accounts[p.reference_account],
           pp_uuid: p.uuid
         })}
      end

    {ctx, ids} = upsert(ctx, :portfolios, existing, incoming, Portfolio)
    Map.merge(ctx, %{portfolios: ids, stale_portfolios: stale(existing, ids)})
  end

  ## Transactions

  defp import_transactions(ctx, client) do
    units = from u in TransactionUnit, order_by: u.id

    existing =
      Repo.all(
        from t in Transaction,
          where: t.user_id == ^ctx.user_id and t.source == :pp_import,
          preload: [units: ^units]
      )
      |> Map.new(&{&1.pp_uuid, &1})

    {ctx, ids} =
      Enum.reduce(client.transactions, {ctx, %{}}, fn t, {ctx, ids} ->
        {ctx, record} = sync_transaction(ctx, existing[t.uuid], t)
        ids = Map.put(ids, t.uuid, record.id)
        # Savings plans may point at either side of a buy.
        ids = if t.other_uuid, do: Map.put(ids, t.other_uuid, record.id), else: ids
        {ctx, ids}
      end)

    stale = stale(existing, ids)
    Repo.delete_all(from t in Transaction, where: t.id in ^stale)

    ctx
    |> count(:transactions, :deleted, length(stale))
    |> Map.put(:transactions, ids)
  end

  defp sync_transaction(ctx, nil, t) do
    record = Repo.insert!(struct(Transaction, transaction_attrs(ctx, t)))
    insert_units(record, Enum.map(t.units, &unit_attrs/1))
    {count(ctx, :transactions, :created), record}
  end

  defp sync_transaction(ctx, record, t) do
    units = Enum.map(t.units, &unit_attrs/1)
    units_changed? = Enum.map(record.units, &unit_attrs/1) != units
    changeset = change(record, transaction_attrs(ctx, t))

    if changeset.changes == %{} and not units_changed? do
      {ctx, record}
    else
      record = Repo.update!(changeset)

      if units_changed? do
        Repo.delete_all(from u in TransactionUnit, where: u.transaction_id == ^record.id)
        insert_units(record, units)
      end

      {count(ctx, :transactions, :updated), record}
    end
  end

  defp transaction_attrs(ctx, t) do
    t
    |> Map.take([:type, :date_time, :shares, :amount, :currency, :ex_date, :note])
    |> Map.merge(%{
      user_id: ctx.user_id,
      portfolio_id: ctx.portfolios[t.portfolio],
      account_id: ctx.accounts[t.account],
      other_portfolio_id: ctx.portfolios[t.other_portfolio],
      other_account_id: ctx.accounts[t.other_account],
      security_id: ctx.securities[t.security],
      source: :pp_import,
      pp_uuid: t.uuid,
      pp_other_uuid: t.other_uuid,
      pp_source: t.source
    })
  end

  defp unit_attrs(u) do
    u
    |> Map.take([:type, :amount, :currency, :fx_amount, :fx_currency])
    |> Map.put(:fx_rate, u.fx_rate && Decimal.normalize(u.fx_rate))
  end

  defp insert_units(_record, []), do: :ok

  defp insert_units(record, units),
    do:
      Repo.insert_all(TransactionUnit, Enum.map(units, &Map.put(&1, :transaction_id, record.id)))

  ## Savings plans

  # PP gives savings plans no UUID, so they are replaced as a whole when anything changed.
  defp import_savings_plans(ctx, client) do
    incoming = Enum.map(client.plans, &plan_attrs(ctx, &1))

    existing =
      Repo.all(from p in SavingsPlan, where: p.user_id == ^ctx.user_id, preload: :transactions)

    if Enum.sort(Enum.map(existing, &normalize_plan/1)) == Enum.sort(incoming) do
      ctx
    else
      Repo.delete_all(from p in SavingsPlan, where: p.user_id == ^ctx.user_id)
      Enum.each(incoming, &insert_plan/1)

      ctx
      |> count(:savings_plans, :deleted, length(existing))
      |> count(:savings_plans, :created, length(incoming))
    end
  end

  @plan_fields [
    :name,
    :note,
    :type,
    :auto_generate,
    :start,
    :interval,
    :amount,
    :fees,
    :taxes,
    :attributes
  ]
  @plan_refs [:user_id, :security_id, :portfolio_id, :account_id]

  defp plan_attrs(ctx, p) do
    p
    |> Map.take(@plan_fields)
    |> Map.merge(%{
      user_id: ctx.user_id,
      security_id: ctx.securities[p.security],
      portfolio_id: ctx.portfolios[p.portfolio],
      account_id: ctx.accounts[p.account],
      transaction_ids:
        p.transactions |> Enum.map(&ctx.transactions[&1]) |> Enum.reject(&is_nil/1) |> uniq_sort()
    })
  end

  defp normalize_plan(plan) do
    plan
    |> Map.take(@plan_fields ++ @plan_refs)
    |> Map.put(:transaction_ids, plan.transactions |> Enum.map(& &1.id) |> uniq_sort())
  end

  defp insert_plan(attrs) do
    {transaction_ids, attrs} = Map.pop!(attrs, :transaction_ids)
    plan = Repo.insert!(struct(SavingsPlan, attrs))
    rows = Enum.map(transaction_ids, &%{savings_plan_id: plan.id, transaction_id: &1})
    Repo.insert_all("depot_savings_plan_transactions", rows)
  end

  defp uniq_sort(list), do: list |> Enum.uniq() |> Enum.sort()

  ## Taxonomies

  defp import_taxonomies(ctx, client) do
    existing =
      Repo.all(from t in Taxonomy, where: t.user_id == ^ctx.user_id and not is_nil(t.pp_id))
      |> Map.new(&{&1.pp_id, &1})

    incoming =
      for t <- client.taxonomies do
        attrs = Map.take(t, [:name, :source, :dimensions])
        {t.id, Map.merge(attrs, %{user_id: ctx.user_id, pp_id: t.id})}
      end

    {ctx, ids} = upsert(ctx, :taxonomies, existing, incoming, Taxonomy)

    ctx =
      Enum.reduce(client.taxonomies, ctx, fn t, ctx ->
        import_classifications(ctx, ids[t.id], t.classifications)
      end)

    stale = stale(existing, ids)
    Repo.delete_all(from t in Taxonomy, where: t.id in ^stale)
    count(ctx, :taxonomies, :deleted, length(stale))
  end

  defp import_classifications(ctx, taxonomy_id, classifications) do
    assignments = from a in Assignment, order_by: a.id

    existing =
      Repo.all(
        from c in Classification,
          where: c.taxonomy_id == ^taxonomy_id,
          preload: [assignments: ^assignments]
      )
      |> Map.new(&{&1.pp_id, &1})

    {ctx, ids} =
      classifications
      |> parents_first()
      |> Enum.reduce({ctx, %{}}, fn c, {ctx, ids} ->
        attrs =
          c
          |> Map.take([:name, :note, :color, :weight, :rank])
          |> Map.merge(%{taxonomy_id: taxonomy_id, parent_id: ids[c.parent_id], pp_id: c.id})

        old = existing[c.id]
        {ctx, record} = put_record(ctx, :classifications, Classification, old, attrs)
        ctx = sync_assignments(ctx, record.id, (old && old.assignments) || [], c.assignments)
        {ctx, Map.put(ids, c.id, record.id)}
      end)

    # Deleting a classification deletes its children too, so delete by id, not record by record.
    stale = stale(existing, ids)
    Repo.delete_all(from c in Classification, where: c.id in ^stale)
    count(ctx, :classifications, :deleted, length(stale))
  end

  defp parents_first(classifications) do
    parents = Map.new(classifications, &{&1.id, &1.parent_id})
    Enum.sort_by(classifications, &depth(parents, &1.parent_id, 0))
  end

  defp depth(_parents, nil, depth), do: depth
  defp depth(_parents, _id, depth) when depth > 100, do: depth
  defp depth(parents, id, depth), do: depth(parents, parents[id], depth + 1)

  # Assignments have no identity in PP, so a changed list replaces the old one.
  defp sync_assignments(ctx, classification_id, current, assignments) do
    incoming =
      for a <- assignments, vehicle = vehicle(ctx, a.vehicle), vehicle != nil do
        Map.merge(vehicle, %{weight: a.weight, rank: a.rank})
      end

    current = Enum.map(current, &Map.take(&1, [:security_id, :account_id, :weight, :rank]))

    if current == incoming do
      ctx
    else
      Repo.delete_all(from a in Assignment, where: a.classification_id == ^classification_id)
      rows = Enum.map(incoming, &Map.put(&1, :classification_id, classification_id))
      Repo.insert_all(Assignment, rows)

      ctx
      |> count(:assignments, :deleted, length(current))
      |> count(:assignments, :created, length(incoming))
    end
  end

  defp vehicle(ctx, uuid) do
    cond do
      id = ctx.securities[uuid] -> %{security_id: id, account_id: nil}
      id = ctx.accounts[uuid] -> %{security_id: nil, account_id: id}
      true -> nil
    end
  end

  ## Deleting what the file no longer has

  defp delete_stale_holdings(ctx) do
    ctx =
      ctx
      |> delete_or_detach(
        :portfolios,
        Portfolio,
        ctx.stale_portfolios,
        :portfolio_id,
        :other_portfolio_id
      )
      |> delete_or_detach(:accounts, Account, ctx.stale_accounts, :account_id, :other_account_id)

    link_ids = Enum.map(ctx.stale_links, & &1.id)
    Repo.delete_all(from l in PPSecurityLink, where: l.id in ^link_ids)

    orphans =
      ctx.stale_links
      |> Enum.map(& &1.security_id)
      |> Enum.uniq()
      |> Enum.filter(&unreferenced?/1)

    Repo.delete_all(from s in Security, where: s.id in ^orphans)

    count(ctx, :securities, :deleted, length(orphans))
  end

  # A portfolio or account PP no longer has stays, detached from PP, while transactions entered
  # in the Depot use it.
  defp delete_or_detach(ctx, kind, schema, ids, field, other_field) do
    {keep, delete} =
      Enum.split_with(ids, fn id ->
        Repo.exists?(
          from t in Transaction,
            where:
              t.source != :pp_import and
                (field(t, ^field) == ^id or field(t, ^other_field) == ^id)
        )
      end)

    Repo.update_all(from(r in schema, where: r.id in ^keep), set: [pp_uuid: nil])
    Repo.delete_all(from r in schema, where: r.id in ^delete)

    ctx
    |> count(kind, :updated, length(keep))
    |> count(kind, :deleted, length(delete))
  end

  # A security stays while any user's file, transaction, plan or assignment still needs it, or
  # any user compares with it.
  defp unreferenced?(security_id) do
    not Enum.any?([PPSecurityLink, Transaction, SavingsPlan, Assignment], fn schema ->
      Repo.exists?(from r in schema, where: r.security_id == ^security_id)
    end) and not Repo.exists?(from s in Setting, where: s.benchmark_id == ^security_id)
  end

  ## Helpers

  defp owned(schema, user_id) do
    Repo.all(from r in schema, where: r.user_id == ^user_id and not is_nil(r.pp_uuid))
    |> Map.new(&{&1.pp_uuid, &1})
  end

  defp stale(existing, ids),
    do: for({key, record} <- existing, not Map.has_key?(ids, key), do: record.id)

  # Inserts or updates records so they match `incoming`, a list of `{key, attrs}`.
  defp upsert(ctx, kind, existing, incoming, schema) do
    Enum.reduce(incoming, {ctx, %{}}, fn {key, attrs}, {ctx, ids} ->
      {ctx, record} = put_record(ctx, kind, schema, existing[key], attrs)
      {ctx, Map.put(ids, key, record.id)}
    end)
  end

  defp put_record(ctx, kind, schema, nil, attrs),
    do: {count(ctx, kind, :created), Repo.insert!(struct(schema, attrs))}

  defp put_record(ctx, kind, _schema, record, attrs), do: update(ctx, kind, record, attrs)

  defp update(ctx, kind, record, attrs) do
    case change(record, attrs) do
      %{changes: changes} when changes == %{} -> {ctx, record}
      changeset -> {count(ctx, kind, :updated), Repo.update!(changeset)}
    end
  end

  defp count(ctx, kind, op, n \\ 1) do
    update_in(ctx, [:summary, kind, op], &(&1 + n))
  end
end

defmodule AbakusWeb.Depot.NewSecurity do
  @moduledoc """
  A security created by its ISIN, as the Buchung dialog and the securities page create one: its
  form (sent as `security`), Yahoo's lookup of name and symbol once a valid ISIN is typed, and the
  help line that says how the lookup went. An ISIN a security already has is not looked up; that
  security is `existing`. The page runs the lookup with `start_async/3`. The ISIN's errors wait
  until all 12 characters are typed or the field is left (`leave_isin/1`).
  """

  import Phoenix.Component, only: [to_form: 2]

  alias Abakus.Depot.{MarketData, Receipts, Securities}
  alias Abakus.Depot.Securities.ISIN

  defstruct [:form, :lookup, :isin, :existing, isin_left: false]

  @doc "A new security with `params` filled in, nothing looked up yet; a given ISIN counts as left."
  def new(params \\ %{}) do
    left = Map.get(params, "isin") not in [nil, ""]
    %__MODULE__{form: form(params, nil, left), isin_left: left}
  end

  @doc """
  Takes the typed `params`, `target` the field that changed. Returns `{:lookup, new_security,
  isin}` when a new valid ISIN is to be looked up, else `{:ok, new_security}`.
  """
  def change(scope, %__MODULE__{} = new_security, params, target) do
    isin = params |> Map.get("isin", "") |> String.replace(" ", "") |> String.upcase()
    existing = if ISIN.valid?(isin), do: Securities.get_security_by_isin(scope, isin)
    left = new_security.isin_left

    cond do
      existing ->
        {:ok,
         %{
           new_security
           | form: form(params, nil, left),
             existing: existing,
             isin: isin,
             lookup: nil
         }}

      target == ["security", "isin"] and isin != new_security.isin and ISIN.valid?(isin) ->
        new_security = %{new_security | form: form(params, :validate, left), existing: nil}
        {:lookup, %{new_security | isin: isin, lookup: :searching}, isin}

      true ->
        {:ok, %{new_security | form: form(params, :validate, left), existing: nil}}
    end
  end

  @doc "The ISIN field was left: its errors show from now on."
  def leave_isin(%__MODULE__{form: form} = new_security) do
    action = if form.params == %{}, do: nil, else: :validate
    %{new_security | form: form(form.params, action, true), isin_left: true}
  end

  @doc """
  Leaves out the ISIN's errors while fewer than its 12 characters are typed and the field still
  has the focus (`left` false), so typing it does not flag it as wrong.
  """
  def hold_isin_errors(%Ecto.Changeset{} = changeset, true = _left), do: changeset

  def hold_isin_errors(%Ecto.Changeset{params: params} = changeset, false) do
    typed = String.replace(Map.get(params || %{}, "isin") || "", " ", "")

    if String.length(typed) < 12,
      do: %{changeset | errors: Keyword.delete(changeset.errors, :isin)},
      else: changeset
  end

  @doc "Looks `isin` up at Yahoo, for `looked_up/2`."
  def lookup(isin), do: {isin, MarketData.lookup_isin(isin)}

  @doc "Fills in what the lookup found; an answer for an ISIN typed over meanwhile changes nothing."
  def looked_up(%__MODULE__{isin: isin} = new_security, {:ok, {isin, {:ok, found}}}) do
    params =
      new_security.form.params
      |> Map.put("isin", isin)
      |> Map.merge(%{"name" => found.name, "symbol" => found.symbol})

    %{new_security | form: form(params, :validate, new_security.isin_left), lookup: :found}
  end

  def looked_up(%__MODULE__{isin: isin} = new_security, {:ok, {isin, {:error, reason}}}),
    do: %{new_security | lookup: {:error, MarketData.lookup_error(reason)}}

  def looked_up(new_security, {:exit, _reason}),
    do: %{new_security | lookup: {:error, MarketData.lookup_error(:unreachable)}}

  def looked_up(new_security, _stale), do: new_security

  @doc """
  Creates the security (`Securities.create_security/2`), fetches its prices and what DivvyDiary
  knows in the background and checks the receipts again; on errors the form shows them.
  """
  def create(scope, %__MODULE__{} = new_security) do
    case Securities.create_security(scope, new_security.form.params) do
      {:ok, security} ->
        if security.quote_feed == :yahoo, do: MarketData.fetch_in_background(security)
        MarketData.fetch_divvy_diary_in_background(security)
        Receipts.recheck(scope)
        {:ok, security}

      {:error, changeset} ->
        {:error, %{new_security | form: to_form(changeset, as: :security)}}
    end
  end

  @doc "The ISIN's help line: what the lookup does, found or why it failed."
  def lookup_text(%__MODULE__{existing: %{name: name}}), do: "Gibt es schon: #{name}."

  def lookup_text(%__MODULE__{lookup: nil, form: form}) do
    if form[:isin].value in [nil, ""], do: "Name und Symbol kommen aus Yahoos Suche."
  end

  def lookup_text(%__MODULE__{lookup: :searching}), do: "Suche bei Yahoo …"
  def lookup_text(%__MODULE__{lookup: :found}), do: "Von Yahoo übernommen, bitte prüfen."
  def lookup_text(%__MODULE__{lookup: {:error, message}}), do: message

  defp form(params, action, left) do
    params
    |> Securities.change_new_security()
    |> Map.put(:action, action)
    |> hold_isin_errors(left)
    |> to_form(as: :security)
  end
end

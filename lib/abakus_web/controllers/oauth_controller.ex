defmodule AbakusWeb.OAuthController do
  @moduledoc """
  Abakus as the OAuth 2.1 authorization server of its apps (ADR 0026, `Abakus.Devices`): the metadata (RFC 8414), the
  authorization page, where the signed-in budget owner confirms an app's sign-in, and the token and revocation
  endpoints. A request naming an unknown client or another redirect is answered here, never redirected (RFC 6749
  4.1.2.1).
  """
  use AbakusWeb, :controller

  alias Abakus.Devices
  alias Abakus.Users.Scope
  alias AbakusWeb.ContentSecurityPolicy

  def metadata(conn, _params) do
    json(conn, %{
      issuer: issuer(),
      authorization_endpoint: url(~p"/oauth/authorize"),
      token_endpoint: url(~p"/oauth/token"),
      revocation_endpoint: url(~p"/oauth/revoke"),
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      revocation_endpoint_auth_methods_supported: ["none"],
      authorization_response_iss_parameter_supported: true
    })
  end

  defp issuer, do: AbakusWeb.Endpoint.url()

  def authorize(conn, params) do
    case authorization_request(params) do
      {:ok, request} ->
        conn
        |> ContentSecurityPolicy.allow_form_target(scheme(request.client))
        |> render(:authorize,
          page_title: "App anmelden",
          request: request,
          owner?: Scope.budget_owner?(conn.assigns.current_scope)
        )

      {:error, :invalid_client} ->
        conn |> put_status(:bad_request) |> render(:invalid_client, page_title: "App anmelden")

      {:error, error, client} ->
        redirect_back(conn, client, params, %{error: error})
    end
  end

  def decide(conn, params) do
    with {:ok, request} <- authorization_request(params),
         "allow" <- params["decision"],
         {:ok, code} <-
           Devices.authorize(
             conn.assigns.current_scope,
             request.client,
             request.device_name,
             request.code_challenge
           ) do
      redirect_back(conn, request.client, params, %{code: code})
    else
      {:error, :invalid_client} ->
        conn |> put_status(:bad_request) |> render(:invalid_client, page_title: "App anmelden")

      {:error, error, client} ->
        redirect_back(conn, client, params, %{error: error})

      _denied ->
        redirect_back(conn, Devices.client(params["client_id"]), params, %{error: "access_denied"})
    end
  end

  defp authorization_request(params) do
    client = Devices.client(params["client_id"])

    cond do
      client == nil or params["redirect_uri"] not in [nil, client.redirect_uri] ->
        {:error, :invalid_client}

      params["response_type"] != "code" ->
        {:error, "unsupported_response_type", client}

      not valid_request?(params) ->
        {:error, "invalid_request", client}

      true ->
        {:ok,
         %{
           client: client,
           device_name: device_name(params["device_name"]),
           code_challenge: params["code_challenge"],
           state: params["state"]
         }}
    end
  end

  defp valid_request?(params) do
    params["code_challenge_method"] == "S256" and
      Devices.code_challenge?(params["code_challenge"]) and
      device_name(params["device_name"]) != nil and
      (is_nil(params["state"]) or is_binary(params["state"]))
  end

  defp device_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      name -> if String.length(name) <= 60, do: name
    end
  end

  defp device_name(_name), do: nil

  defp scheme(client),
    do: client.redirect_uri |> URI.parse() |> Map.fetch!(:scheme) |> Kernel.<>(":")

  defp redirect_back(conn, client, params, answer) do
    query =
      answer
      |> Map.put(:iss, issuer())
      |> then(&if is_binary(params["state"]), do: Map.put(&1, :state, params["state"]), else: &1)
      |> URI.encode_query()

    redirect(conn, external: "#{client.redirect_uri}?#{query}")
  end

  def token(conn, %{"grant_type" => grant_type} = params) do
    cond do
      Devices.client(params["client_id"]) == nil ->
        token_error(conn, :unauthorized, "invalid_client")

      grant_type == "authorization_code" ->
        params["client_id"]
        |> Devices.exchange_code(params["code"], params["code_verifier"])
        |> token_response(conn)

      grant_type == "refresh_token" ->
        params["client_id"] |> Devices.refresh(params["refresh_token"]) |> token_response(conn)

      true ->
        token_error(conn, :bad_request, "unsupported_grant_type")
    end
  end

  def token(conn, _params), do: token_error(conn, :bad_request, "invalid_request")

  defp token_response({:ok, tokens}, conn) do
    conn
    |> no_store()
    |> json(%{
      access_token: tokens.access_token,
      token_type: "Bearer",
      expires_in: tokens.expires_in,
      refresh_token: tokens.refresh_token,
      device_id: tokens.device_id
    })
  end

  defp token_response({:error, :invalid_grant}, conn),
    do: token_error(conn, :bad_request, "invalid_grant")

  defp token_error(conn, status, error),
    do: conn |> no_store() |> put_status(status) |> json(%{error: error})

  defp no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end

  @doc "Signs out the device of the token (RFC 7009); answers alike whether or not the token was valid."
  def revoke(conn, params) do
    if Devices.client(params["client_id"]) do
      Devices.revoke(params["token"])
      conn |> no_store() |> send_resp(:ok, "")
    else
      token_error(conn, :unauthorized, "invalid_client")
    end
  end
end

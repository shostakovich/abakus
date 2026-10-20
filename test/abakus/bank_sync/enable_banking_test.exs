defmodule Abakus.BankSync.EnableBankingTest do
  # Sets the app environment.
  use ExUnit.Case, async: false

  alias Abakus.BankSync.EnableBanking

  # A small Enable Banking: answers only requests whose JWT verifies with the application's public key.
  defmodule Stub do
    @behaviour Plug

    import Plug.Conn

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, %{public_key: public_key, requests: requests}) do
      conn = fetch_query_params(conn)

      if authorized?(conn, public_key) do
        {:ok, body, conn} = read_body(conn)
        Agent.update(requests, &(&1 ++ [{conn.method, conn.request_path, body}]))
        conn |> assign(:body, body) |> route(conn.method, conn.path_info)
      else
        send_resp(conn, 401, ~s({"message": "Invalid JWT"}))
      end
    end

    defp authorized?(conn, public_key) do
      with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
           [header, claims, signature] <- String.split(token, "."),
           {:ok, signature} <- Base.url_decode64(signature, padding: false) do
        :public_key.verify(header <> "." <> claims, :sha256, signature, public_key)
      else
        _other -> false
      end
    end

    defp route(conn, "GET", ["aspsps"]) do
      %{"country" => "DE", "psu_type" => "personal"} = conn.query_params

      json(conn, 200, %{
        aspsps: [
          %{
            name: "Musterbank",
            country: "DE",
            maximum_consent_validity: 15_552_000,
            psu_types: ["personal", "business"]
          },
          %{name: "Firmenbank", country: "DE", psu_types: ["business"]}
        ]
      })
    end

    defp route(conn, "POST", ["auth"]) do
      scheme = if JSON.decode!(conn.assigns.body)["state"] == "plain", do: "http", else: "https"
      json(conn, 200, %{url: "#{scheme}://bank.example/consent?id=1", authorization_id: "a-1"})
    end

    defp route(conn, "POST", ["sessions"]) do
      json(conn, 200, %{
        session_id: "session-1",
        access: %{valid_until: "2027-04-18T10:00:00.000000+00:00"},
        accounts: [
          %{uid: "uid-1", name: "Girokonto", account_id: %{iban: "DE02100200300000004711"}},
          %{uid: "uid-2", product: "Kreditkarte", account_id: %{other: %{identification: "1"}}}
        ]
      })
    end

    defp json(conn, status, body) do
      conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(body))
    end
  end

  setup do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    {:RSAPrivateKey, _version, modulus, exponent, _d, _p, _q, _e1, _e2, _c, _other} = key

    dir =
      Path.join(System.tmp_dir!(), "abakus-enable-banking-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    key_file = Path.join(dir, "private.pem")

    File.write!(
      key_file,
      :public_key.pem_encode([:public_key.pem_entry_encode(:PrivateKeyInfo, key)])
    )

    requests = start_supervised!({Agent, fn -> [] end})

    server =
      {Bandit,
       plug: {Stub, %{public_key: {:RSAPublicKey, modulus, exponent}, requests: requests}},
       ip: :loopback,
       port: 0,
       startup_log: false}

    {:ok, {_ip, port}} = server |> start_supervised!() |> ThousandIsland.listener_info()

    configure(app_id: "app-1", key_file: key_file, base_url: "http://127.0.0.1:#{port}")

    on_exit(fn ->
      Application.delete_env(:abakus, EnableBanking)
      File.rm_rf!(dir)
    end)

    %{requests: requests, key_file: key_file}
  end

  defp configure(config), do: Application.put_env(:abakus, EnableBanking, config)

  test "is available with the application id and the key file", %{key_file: key_file} do
    assert EnableBanking.available?()

    configure(app_id: nil, key_file: key_file)
    refute EnableBanking.available?()
    assert EnableBanking.banks("DE") == {:error, :not_configured}
  end

  test "lists the banks for personal accounts" do
    assert EnableBanking.banks("DE") ==
             {:ok, [%{name: "Musterbank", country: "DE", maximum_consent_validity: 15_552_000}]}
  end

  test "starts a consent at the bank", %{requests: requests} do
    assert EnableBanking.start_auth(%{
             bank: %{name: "Musterbank", country: "DE"},
             valid_until: ~U[2027-04-18 10:00:00Z],
             redirect_url: "https://abakus.example/budget/bank-connections/callback",
             state: "state-1"
           }) == {:ok, "https://bank.example/consent?id=1"}

    assert [{"POST", "/auth", body}] = Agent.get(requests, & &1)

    assert JSON.decode!(body) == %{
             "access" => %{"valid_until" => "2027-04-18T10:00:00Z"},
             "aspsp" => %{"name" => "Musterbank", "country" => "DE"},
             "state" => "state-1",
             "redirect_url" => "https://abakus.example/budget/bank-connections/callback",
             "psu_type" => "personal"
           }
  end

  test "refuses a consent URL that is not https" do
    assert EnableBanking.start_auth(%{
             bank: %{name: "Musterbank", country: "DE"},
             valid_until: ~U[2027-04-18 10:00:00Z],
             redirect_url: "https://abakus.example/budget/bank-connections/callback",
             state: "plain"
           }) == {:error, :invalid_response}
  end

  test "opens the session of a code with the bank's accounts", %{requests: requests} do
    assert EnableBanking.create_session("code-1") ==
             {:ok,
              %{
                session_id: "session-1",
                valid_until: ~U[2027-04-18 10:00:00.000000Z],
                accounts: [
                  %{uid: "uid-1", name: "Girokonto", iban: "DE02100200300000004711"},
                  %{uid: "uid-2", name: "Kreditkarte", iban: nil}
                ]
              }}

    assert [{"POST", "/sessions", ~s|{"code":"code-1"}|}] = Agent.get(requests, & &1)
  end

  test "tells a refused request by its status", %{key_file: key_file} do
    other_key = :public_key.generate_key({:rsa, 2048, 65_537})

    File.write!(
      key_file,
      :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, other_key)])
    )

    assert EnableBanking.banks("DE") == {:error, {:http_status, 401}}
  end

  test "tells a key file that is missing or no key", %{key_file: key_file} do
    File.write!(key_file, "no key")
    assert EnableBanking.banks("DE") == {:error, :invalid_key}

    File.rm!(key_file)
    assert EnableBanking.banks("DE") == {:error, :key_unreadable}
  end
end

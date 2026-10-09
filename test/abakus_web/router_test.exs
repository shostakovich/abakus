defmodule AbakusWeb.RouterTest do
  use AbakusWeb.ConnCase

  # The only routes an anonymous visitor may use. A new public route belongs here, on purpose.
  @public [
    {:get, "/up"},
    {:get, "/users/log-in"},
    {:get, "/users/log-in/:token"},
    {:post, "/users/log-in"},
    {:post, "/users/passkeys/options"},
    {:delete, "/users/log-out"}
  ]

  defp public?(%{verb: verb, path: path}) do
    {verb, path} in @public or
      (Application.get_env(:abakus, :dev_routes) && String.starts_with?(path, "/dev/"))
  end

  test "every other route turns an anonymous visitor away" do
    routes = Enum.reject(AbakusWeb.Router.__routes__(), &public?/1)

    assert %{verb: :get, path: "/"} in Enum.map(routes, &Map.take(&1, [:verb, :path]))
    assert Enum.any?(routes, &(&1.verb == :post))

    for %{verb: verb, path: path} <- routes do
      # Fill in route parameters such as `:token`.
      concrete = String.replace(path, ~r"[:*]\w+", "x")
      method = if verb == :*, do: "GET", else: verb |> to_string() |> String.upcase()
      conn = dispatch(build_conn(), @endpoint, method, concrete, nil)

      assert turned_away?(conn), "#{method} #{path} answered #{conn.status} without a session"
    end
  end

  # Pages redirect to the sign-in page; the JSON endpoints of the passkey hooks answer 401.
  defp turned_away?(conn) do
    case conn.status do
      302 -> get_resp_header(conn, "location") == [~p"/users/log-in"]
      401 -> JSON.decode!(conn.resp_body) == %{"error" => "session"}
      _ -> false
    end
  end

  test "the public routes exist" do
    routes = for route <- AbakusWeb.Router.__routes__(), do: {route.verb, route.path}

    for route <- @public, do: assert(route in routes)
  end
end

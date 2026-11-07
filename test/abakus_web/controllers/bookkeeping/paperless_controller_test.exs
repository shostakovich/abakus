defmodule AbakusWeb.Bookkeeping.PaperlessControllerTest do
  use AbakusWeb.ConnCase

  import Abakus.DomainFixtures

  alias Abakus.{Bookkeeping, FakePaperless, Paperless}

  @url "http://paperless.test"

  setup :register_and_log_in_user

  setup %{scope: scope} do
    {:ok, _ids} =
      Bookkeeping.put_business_accounts(scope, [account_fixture(kind: :tracking).id])

    FakePaperless.serve(%{
      @url => %{
        token: "t",
        documents: [
          FakePaperless.fixture(7, [], pdf: "%PDF-1.4 Beleg"),
          FakePaperless.fixture(8, [], pdf: <<0x89, "PNG\r\n", 0x1A, "\n", "Bild">>),
          FakePaperless.fixture(9, [], pdf: "<html><script>alert(1)</script></html>")
        ]
      }
    })

    :ok
  end

  test "shows a document of the user's Paperless as PDF", %{conn: conn, scope: scope} do
    {:ok, _connection} = Paperless.update_connection(scope, %{"url" => @url, "token" => "t"})

    conn = get(conn, ~p"/buchhaltung/paperless/7")

    assert response(conn, 200) == "%PDF-1.4 Beleg"
    assert response_content_type(conn, :pdf) =~ "application/pdf"
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "inline"

    assert conn |> recycle() |> get(~p"/buchhaltung/paperless/10") |> response(404)
    assert conn |> recycle() |> get(~p"/buchhaltung/paperless/x") |> response(404)
    assert conn |> recycle() |> get(~p"/buchhaltung/paperless/-7") |> response(404)
  end

  test "shows an image as what its bytes are, and nothing else", %{conn: conn, scope: scope} do
    {:ok, _connection} = Paperless.update_connection(scope, %{"url" => @url, "token" => "t"})

    image = get(conn, ~p"/buchhaltung/paperless/8")
    assert response_content_type(image, :png) =~ "image/png"
    assert get_resp_header(image, "content-disposition") |> hd() =~ "Paperless%208.png"

    assert image |> recycle() |> get(~p"/buchhaltung/paperless/9") |> response(502) ==
             "Paperless hat keine PDF- oder Bilddatei geliefert."
  end

  test "tells a Paperless that fails from a missing document", %{conn: conn, scope: scope} do
    {:ok, _connection} =
      Paperless.update_connection(scope, %{"url" => "http://weg.test", "token" => "t"})

    assert conn |> get(~p"/buchhaltung/paperless/7") |> response(502) ==
             "Paperless ist gerade nicht erreichbar."
  end

  test "shows nothing without Paperless", %{conn: conn} do
    assert conn |> get(~p"/buchhaltung/paperless/7") |> response(404)
  end
end

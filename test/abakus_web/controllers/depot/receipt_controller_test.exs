defmodule AbakusWeb.Depot.ReceiptControllerTest do
  use AbakusWeb.ConnCase

  import Abakus.Depot.PortfoliosFixtures
  import Abakus.UsersFixtures

  alias Abakus.Depot.Portfolios

  @pdf "%PDF-1.4\nBeleg\n%%EOF\n"

  setup :register_and_log_in_user

  setup %{scope: scope} do
    path = Path.join(System.tmp_dir!(), "receipt-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, @pdf)
    on_exit(fn -> File.rm(path) end)

    account = account_fixture(scope)
    portfolio_fixture(scope, reference_account_id: account.id)

    params = %{
      "kind" => "deposit",
      "date" => "2026-10-01",
      "amount" => "1",
      "account_id" => account.id
    }

    {:ok, [deposit]} =
      Portfolios.book_transaction(
        scope,
        Portfolios.transaction_choices(scope),
        params,
        {path, "beleg.pdf"}
      )

    %{receipt_id: deposit.receipt_id}
  end

  test "shows the user's receipt inline", %{conn: conn, receipt_id: id} do
    conn = get(conn, ~p"/depot/receipts/#{id}")

    assert response(conn, 200) == @pdf
    assert response_content_type(conn, :pdf) =~ "application/pdf"
    assert get_resp_header(conn, "content-disposition") == [~s(inline; filename="beleg.pdf")]
  end

  test "not another user's receipt, nor an unknown one", %{conn: conn, receipt_id: id} do
    other = user_fixture()
    portfolio_fixture(user_scope_fixture(other))

    assert build_conn() |> log_in_user(other) |> get(~p"/depot/receipts/#{id}") |> response(404)
    assert conn |> get(~p"/depot/receipts/x") |> response(404)
    assert conn |> get(~p"/depot/receipts/99999999999999999999") |> response(404)
  end

  test "not without the Depot", %{receipt_id: id} do
    conn = log_in_user(build_conn(), user_fixture())
    assert_error_sent 404, fn -> get(conn, ~p"/depot/receipts/#{id}") end
  end

  test "not a receipt whose file is missing", %{conn: conn, scope: scope, receipt_id: id} do
    scope |> Portfolios.get_receipt(id) |> Portfolios.receipt_file() |> File.rm!()

    assert conn |> get(~p"/depot/receipts/#{id}") |> response(404) == "Beleg nicht gefunden"
  end
end

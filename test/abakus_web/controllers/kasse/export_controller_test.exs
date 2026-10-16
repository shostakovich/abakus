defmodule AbakusWeb.Kasse.ExportControllerTest do
  use AbakusWeb.ConnCase

  import Abakus.KasseFixtures

  alias Abakus.Kasse.Expenses

  setup %{conn: conn} do
    anna = person!("Anna")

    {:ok, _expense} =
      Expenses.create_expense(anna.id, %{
        title: "Rewe",
        date: ~D[2026-09-01],
        paid_by_id: anna.id,
        amount_cents: 1000,
        parts: [%{participant_id: anna.id, weight: 0}]
      })

    %{conn: log_in_participant(conn, anna.id)}
  end

  defp download(conn, path, type, filename) do
    conn = get(conn, path)

    assert {conn.status, get_resp_header(conn, "content-type"),
            get_resp_header(conn, "content-disposition"), get_resp_header(conn, "cache-control")} ==
             {200, [type], [~s(attachment; filename="#{filename}")], ["no-store"]}

    conn.resp_body
  end

  test "downloads the exports of a period with German file names", %{conn: conn} do
    period = "?from=2026-09-01&to=2026-09-30"
    suffix = "2026-09-01_2026-09-30"

    assert download(
             conn,
             "/settings/kasse/export/expenses.csv" <> period,
             "text/csv; charset=utf-8",
             "kasse-ausgaben-#{suffix}.csv"
           ) =~
             "1;01.09.2026;Rewe"

    assert download(
             conn,
             "/settings/kasse/export/expenses.json" <> period,
             "application/json; charset=utf-8",
             "kasse-ausgaben-#{suffix}.json"
           )
           |> JSON.decode!()
           |> Map.fetch!("from") == "2026-09-01"
  end

  test "sends an invalid period back to the export page", %{conn: conn} do
    for path <- ~w(/settings/kasse/export/expenses.csv /settings/kasse/export/expenses.json) do
      conn = get(conn, path <> "?from=2026-09-30&to=2026-09-01")

      assert redirected_to(conn, 303) == "/settings/kasse/export?from=2026-09-30&to=2026-09-01"
      assert get_resp_header(conn, "content-disposition") == []

      assert redirected_to(get(conn, path <> "?from=broken"), 303) ==
               "/settings/kasse/export?from=broken"
    end
  end
end

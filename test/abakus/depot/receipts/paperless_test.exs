defmodule Abakus.Depot.Receipts.PaperlessTest do
  use Abakus.DataCase

  # Failing instances and documents are logged.
  @moduletag :capture_log

  import Abakus.Depot.ReceiptsFixtures
  import Abakus.UsersFixtures

  alias Abakus.Depot.{FakeModel, FakePaperless, FakeTextExtractor, Receipts, Settings}
  alias Abakus.Depot.Portfolios.Receipt
  alias Abakus.Depot.Receipts.PaperlessJob

  @url "http://paperless.test"

  defp paperless_user(tag, url \\ @url, token \\ "token") do
    scope = user_scope_fixture()

    {:ok, _setting} =
      Settings.update_paperless(scope, %{
        "paperless_url" => url,
        "paperless_token" => token,
        "paperless_tag" => tag
      })

    scope
  end

  defp inbox(scope), do: Receipts.list_inbox(scope)

  defp polled_at(scope), do: Settings.get_settings(scope).paperless_polled_at

  defp tags(id), do: FakePaperless.documents(@url) |> Enum.find(&(&1.id == id)) |> Map.get(:tags)

  defp poll_all do
    PaperlessJob.poll_all()
    await_recognition()
  end

  setup do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    :ok
  end

  test "takes only documents with the user's tag, swaps the tag and assigns them to the user who configured it" do
    first = paperless_user("abakus")
    second = paperless_user("belege")

    FakePaperless.serve(%{
      @url => %{
        token: "token",
        documents: [
          FakePaperless.document(4812, ["abakus", "Bank"]),
          FakePaperless.document(4813, ["belege"], filename: nil),
          FakePaperless.document(4814, ["Rechnung"])
        ]
      }
    })

    poll_all()

    assert [%Receipt{paperless_id: 4812, filename: "scan-4812.pdf", status: :ready}] =
             inbox(first)

    assert [%Receipt{paperless_id: 4813, filename: "Paperless 4813.pdf"}] = inbox(second)
    assert tags(4812) == ["Bank", "abakus-erledigt"]
    assert tags(4813) == ["belege-erledigt"]
    assert tags(4814) == ["Rechnung"]
    assert polled_at(first)
  end

  test "Scenario: Paperless tag swapped — a document in the inbox is tagged „-erledigt“ instead" do
    user = paperless_user("abakus")

    FakePaperless.serve(%{
      @url => %{token: "token", documents: [FakePaperless.document(1, ["abakus"])]}
    })

    poll_all()
    assert [_receipt] = inbox(user)
    assert tags(1) == ["abakus-erledigt"]

    poll_all()
    assert [_one] = inbox(user)
  end

  test "a document whose tag swap failed lands once and has its tag swapped on the next poll" do
    user = paperless_user("abakus")
    document = FakePaperless.document(1, ["abakus"], swap_fails: true)
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()
    assert [_receipt] = inbox(user)
    assert tags(1) == ["abakus"]

    FakePaperless.update_document(@url, 1, swap_fails: false)
    poll_all()

    assert [_one] = inbox(user)
    assert tags(1) == ["abakus-erledigt"]
  end

  test "a discarded document stays discarded while its tag swap keeps failing" do
    user = paperless_user("abakus")
    document = FakePaperless.document(1, ["abakus"], swap_fails: true)
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()
    [receipt] = inbox(user)
    :ok = Receipts.discard(user, receipt.id)

    poll_all()
    poll_all()

    assert inbox(user) == []
    assert Repo.get!(Receipt, receipt.id).status == :discarded

    FakePaperless.update_document(@url, 1, swap_fails: false)
    poll_all()

    assert inbox(user) == []
    assert tags(1) == ["abakus-erledigt"]
  end

  test "has the model read Paperless' text, not the PDF's" do
    FakeTextExtractor.stub("pdftotext")
    user = paperless_user("abakus")
    document = FakePaperless.document(1, ["abakus"], content: receipt_text("PL-1"))
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()

    assert_received {:answer, text}
    assert text == receipt_text("PL-1")
    assert [%Receipt{text: ^text}] = inbox(user)
  end

  test "reads the PDF's text when Paperless has none" do
    FakeTextExtractor.stub("pdftotext")
    paperless_user("abakus")
    document = FakePaperless.document(1, ["abakus"], content: "  ")
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()

    assert_received {:answer, "pdftotext"}
  end

  test "a file uploaded already lands once and still loses its tag" do
    user = paperless_user("abakus")
    document = FakePaperless.document(1, ["abakus"])
    path = pdf_file("beleg.pdf", document.pdf)
    {:ok, :added} = Receipts.upload(user, path, "beleg.pdf")
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()

    assert [%Receipt{filename: "beleg.pdf"}] = inbox(user)
    assert tags(1) == ["abakus-erledigt"]
  end

  test "one failing instance or document, or one too large, does not stop the others" do
    unreachable = paperless_user("abakus", "http://unreachable.test")
    wrong_token = paperless_user("abakus", @url, "wrong")
    user = paperless_user("abakus")

    FakePaperless.serve(%{
      @url => %{
        token: "token",
        documents: [
          FakePaperless.document(1, ["abakus"], raise: true),
          FakePaperless.document(2, ["abakus"], pdf: "no PDF"),
          FakePaperless.document(3, ["abakus"]),
          FakePaperless.document(4, ["abakus"],
            pdf: "%PDF-1.4\n" <> String.duplicate(" ", 20_000_000)
          )
        ]
      }
    })

    poll_all()

    assert [%Receipt{paperless_id: 3}] = inbox(user)
    assert tags(1) == ["abakus"]
    assert tags(2) == ["abakus"]
    assert tags(4) == ["abakus"]
    assert inbox(unreachable) == [] and inbox(wrong_token) == []
    refute polled_at(unreachable)
  end
end

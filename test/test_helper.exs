# Tests of PDFs need the tools the image installs: poppler's pdftotext, and Typst for invoices.
exclude =
  [pdftotext: ["pdftotext"], typst: ["typst", "pdfinfo", "pdfdetach"]]
  |> Enum.reject(fn {_tag, tools} -> Enum.all?(tools, &System.find_executable/1) end)
  |> Keyword.keys()

ExUnit.start(assert_receive_timeout: 1_000, exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Abakus.Repo, :manual)

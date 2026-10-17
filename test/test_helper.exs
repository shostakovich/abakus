# The Depot's pdftotext tests need poppler's pdftotext, as the image installs it.
exclude = if System.find_executable("pdftotext"), do: [], else: [:pdftotext]

ExUnit.start(assert_receive_timeout: 1_000, exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Abakus.Repo, :manual)

# Tests against the owner's real PP file run only when the environment gives what they need; their
# moduledocs say how. The Depot's pdftotext tests need poppler's pdftotext, as the image installs it.
exclude =
  [
    pp_file: ~w(PP_FILE),
    pp_net_worth: ~w(PP_FILE PP_NET_WORTH_DATE PP_NET_WORTH),
    pp_dividends: ~w(PP_FILE PP_DIVIDENDS),
    pp_yearly_ttwror: ~w(PP_FILE PP_YEARLY_TTWROR)
  ]
  |> Enum.reject(fn {_tag, variables} -> Enum.all?(variables, &System.get_env/1) end)
  |> Keyword.keys()
  |> Enum.concat(if System.find_executable("pdftotext"), do: [], else: [:pdftotext])

ExUnit.start(assert_receive_timeout: 1_000, exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Abakus.Repo, :manual)

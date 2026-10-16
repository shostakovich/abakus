defmodule AbakusWeb.PlushTest do
  use ExUnit.Case, async: true

  alias AbakusWeb.Plush

  test "the plush names and the image files match" do
    dir = Application.app_dir(:abakus, "priv/static/images/plush")
    files = dir |> Path.join("*.webp") |> Path.wildcard() |> Enum.map(&Path.basename(&1, ".webp"))

    assert Plush.names() -- files == []
    assert files -- Plush.names() == []
  end

  test "a plush is the same image in both themes; unknown names have none" do
    assert Plush.src("receipt", :light) =~ ~r"^/images/plush/receipt"
    assert Plush.src("receipt", :dark) == nil
    assert Plush.src("nope", :light) == nil
  end
end

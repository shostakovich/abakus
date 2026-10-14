defmodule AbakusWeb.Icons do
  @moduledoc """
  The app's Lucide icons, compiled from `assets/vendor/lucide` (lucide-static, ISC licence).
  `<.icon name="…">` looks names up here first, then in `Setzkasten.Lucide`; an unknown name
  raises. To add one, copy `icons/<name>.svg` from lucide-static into the directory.
  """
  use Setzkasten.Icons, path: "assets/vendor/lucide"
end

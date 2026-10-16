defmodule AbakusWeb.Depot.ComponentsTest do
  use ExUnit.Case, async: true

  alias AbakusWeb.Depot.Components

  test "an amount's tone follows its sign as shown, muted when it rounds to zero" do
    assert Components.amount_tone(56_200, 0) == "text-success-ink"
    assert Components.amount_tone(-40) == "text-error-ink"
    assert Components.amount_tone(-40, 0) == "text-base-content/70"
    assert Components.amount_tone(0) == "text-base-content/70"
  end
end

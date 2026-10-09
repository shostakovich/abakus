defmodule Abakus.Users.PasskeyTest do
  use ExUnit.Case, async: true

  alias Abakus.Users.Passkey

  @invisible "Der Name darf keine Steuer- oder unsichtbaren Zeichen enthalten."
  @name "Bitte gib dem Passkey einen Namen (höchstens 60 Zeichen)."

  test "accepts trimmed names up to 60 characters, emoji sequences included" do
    for name <- [
          "iPhone",
          " iPhone ",
          "Mac mini (Büro)",
          String.duplicate("x", 60),
          "\u{1F469}\u200D\u{1F4BB} Laptop",
          "\u{1F468}\u{1F3FD}\u200D\u{1F4BB} Arbeit",
          "\u{1F468}\u200D\u{1F469}\u200D\u{1F467} Familie",
          "\u{1F3F3}\uFE0F\u200D\u{1F308} Tablet",
          "\u2764\uFE0F Handy",
          "\u{1F44D}\u{1F3FD}"
        ] do
      assert Passkey.name_error(name) == nil, "expected #{inspect(name)} to be valid"
    end
  end

  test "asks for a name that is missing or too long" do
    for name <- [nil, "", "   ", String.duplicate("x", 61), ["x"]] do
      assert Passkey.name_error(name) == @name, "message for #{inspect(name)}"
    end
  end

  test "refuses control, format and separator characters" do
    for char <- [
          "\n",
          "\r",
          "\t",
          "\u0000",
          "\u007F",
          "\u0085",
          "\u2028",
          "\u2029",
          "\u202E",
          "\u200B",
          "\u200D",
          "\u{E0041}",
          "\uFEFF"
        ] do
      name = "Mac" <> char <> "mini"
      assert Passkey.name_error(name) == @invisible, "message for #{inspect(name)}"
    end

    # A joiner only belongs between two emoji.
    assert Passkey.name_error("Mac \u200D") == @invisible
    assert Passkey.name_error("\u200D\u{1F469}") == @invisible
    assert Passkey.name_error(<<"Mac", 0xFF>>) == @invisible
  end

  test "the changeset refuses them, too" do
    changeset = Passkey.create_changeset(%Passkey{}, %{name: "a\u2028b"})

    assert {"darf keine Steuer- oder unsichtbaren Zeichen enthalten", _opts} =
             changeset.errors[:name]
  end
end

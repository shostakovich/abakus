defmodule AbakusWeb.CoreComponents do
  @moduledoc false
  use Phoenix.Component

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :class, :any, default: nil
  attr :as, :string, default: "section"
  attr :level, :integer, default: 2
  attr :rest, :global
  slot :inner_block

  def card(assigns) do
    ~H"""
    <.dynamic_tag tag_name={@as} class={["card", "mb-3", @class]} {@rest}>
      <div class="card-body">
        <%= if present?(@title) do %>
          <.dynamic_tag tag_name={"h#{@level}"} class="card-title">{@title}</.dynamic_tag>
          <p :if={present?(@subtitle)} class="card-subtitle">{@subtitle}</p>
        <% end %>
        {render_slot(@inner_block)}
      </div>
    </.dynamic_tag>
    """
  end

  attr :id, :string, doc: "the optional id of the flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"
  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "alert alert-dismissible d-flex align-items-start gap-2 mb-3",
        @kind == :info && "alert-success",
        @kind == :error && "alert-danger"
      ]}
      {@rest}
    >
      <div>
        <strong :if={@title} class="d-block">{@title}</strong>
        {msg}
      </div>
      <button type="button" class="btn-close" aria-label="Schließen"></button>
    </div>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="Keine Verbindung"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Verbindung wird wiederhergestellt …
      </.flash>
      <.flash
        id="server-error"
        kind={:error}
        title="Etwas ist schiefgelaufen"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Verbindung wird wiederhergestellt …
      </.flash>
    </div>
    """
  end

  attr :variant, :string, default: "primary", doc: "the felt-css button variant (btn-<variant>)"
  attr :size, :string, default: nil, values: [nil, "sm", "lg"]
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form)

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :classes, [
        "btn",
        "btn-#{assigns.variant}",
        assigns.size && "btn-#{assigns.size}",
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@classes} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button class={@classes} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :switch, :boolean, default: false, doc: "a checkbox drawn as a switch"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "extra classes for the control"
  attr :wrapper_class, :any, default: "mb-3"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={["form-check", @switch && "form-switch", @wrapper_class]}>
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        role={@switch && "switch"}
        class={["form-check-input", @errors != [] && "is-invalid", @class]}
        {@rest}
      />
      <label :if={@label} class="form-check-label" for={@id}>{@label}</label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="form-label" for={@id}>{@label}</label>
      <select
        id={@id}
        name={@name}
        class={["form-select", @errors != [] && "is-invalid", @class]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="form-label" for={@id}>{@label}</label>
      <textarea
        id={@id}
        name={@name}
        class={["form-control", @errors != [] && "is-invalid", @class]}
        {@rest}
      >{Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="form-label" for={@id}>{@label}</label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={[
          if(@type == "range", do: "form-range", else: "form-control"),
          @type == "color" && "form-control-color",
          @errors != [] && "is-invalid",
          @class
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <div class="invalid-feedback d-block">{render_slot(@inner_block)}</div>
    """
  end

  attr :class, :any, default: nil
  attr :title_class, :any, default: nil
  slot :inner_block, required: true
  slot :leading
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={["d-flex align-items-center gap-2 mb-3", @class]}>
      {render_slot(@leading)}
      <h1 class={["h2 mb-0 me-auto", @title_class]}>{render_slot(@inner_block)}</h1>
      {render_slot(@actions)}
    </header>
    """
  end

  @doc "German messages from the validation pass through; Ecto's English ones are translated."
  @spec translate_error({String.t(), keyword}) :: String.t()
  def translate_error({msg, opts}) do
    # Errors from database constraints carry `constraint:` instead of `validation:`.
    (Keyword.get(opts, :validation) || Keyword.get(opts, :constraint))
    |> german(msg, opts)
    |> interpolate(opts)
  end

  defp german(:required, "can't be blank", _opts), do: "muss ausgefüllt werden"
  defp german(:format, "has invalid format", _opts), do: "hat ein ungültiges Format"
  defp german(:inclusion, "is invalid", _opts), do: "ist kein gültiger Wert"
  defp german(:subset, "has an invalid entry", _opts), do: "enthält einen ungültigen Eintrag"
  defp german(:exclusion, "is reserved", _opts), do: "ist nicht erlaubt"
  defp german(:acceptance, "must be accepted", _opts), do: "muss akzeptiert werden"
  defp german(:confirmation, "does not match confirmation", _opts), do: "stimmt nicht überein"

  defp german(key, "is invalid", _opts) when key in [:cast, :assoc, :embed, :check],
    do: "ist ungültig"

  defp german(key, "has already been taken", _opts) when key in [:unique, :unsafe_unique],
    do: "ist bereits vergeben"

  defp german(key, "does not exist", _opts) when key in [:foreign, :assoc],
    do: "existiert nicht"

  defp german(:no_assoc, "is still associated with this entry", _opts),
    do: "ist noch mit diesem Eintrag verknüpft"

  defp german(:no_assoc, "are still associated with this entry", _opts),
    do: "sind noch mit diesem Eintrag verknüpft"

  defp german(:number, "must be less than %{number}", _opts),
    do: "muss kleiner als %{number} sein"

  defp german(:number, "must be greater than %{number}", _opts),
    do: "muss größer als %{number} sein"

  defp german(:number, "must be less than or equal to %{number}", _opts),
    do: "darf höchstens %{number} sein"

  defp german(:number, "must be greater than or equal to %{number}", _opts),
    do: "muss mindestens %{number} sein"

  defp german(:number, "must be equal to %{number}", _opts), do: "muss %{number} sein"
  defp german(:number, "must be not equal to %{number}", _opts), do: "darf nicht %{number} sein"

  defp german(:length, "should be at least %{count} character(s)", _opts),
    do: "muss mindestens %{count} Zeichen lang sein"

  defp german(:length, "should be at most %{count} character(s)", _opts),
    do: "darf höchstens %{count} Zeichen lang sein"

  defp german(:length, "should be %{count} character(s)", _opts),
    do: "muss genau %{count} Zeichen lang sein"

  defp german(:length, "should be at least %{count} byte(s)", opts),
    do: "muss mindestens %{count} #{unit(opts, "Byte", "Bytes")} lang sein"

  defp german(:length, "should be at most %{count} byte(s)", opts),
    do: "darf höchstens %{count} #{unit(opts, "Byte", "Bytes")} lang sein"

  defp german(:length, "should be %{count} byte(s)", opts),
    do: "muss genau %{count} #{unit(opts, "Byte", "Bytes")} lang sein"

  defp german(:length, "should have at least %{count} item(s)", opts),
    do: "braucht mindestens %{count} #{unit(opts, "Eintrag", "Einträge")}"

  defp german(:length, "should have at most %{count} item(s)", opts),
    do: "darf höchstens %{count} #{unit(opts, "Eintrag", "Einträge")} haben"

  defp german(:length, "should have %{count} item(s)", opts),
    do: "braucht genau %{count} #{unit(opts, "Eintrag", "Einträge")}"

  defp german(_key, msg, _opts), do: msg

  defp unit(opts, one, many), do: if(opts[:count] == 1, do: one, else: many)

  defp interpolate(msg, opts) do
    Regex.replace(~r/%{(\w+)}/, msg, fn whole, key -> option_text(opts, key, whole) end)
  end

  defp option_text(opts, key, fallback) do
    case Enum.find(opts, fn {name, _} -> Atom.to_string(name) == key end) do
      {_, value} -> to_string(value)
      nil -> fallback
    end
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js, to: selector, time: 200, transition: {"fade", "opacity-0", "opacity-100"})
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js, to: selector, time: 200, transition: {"fade", "opacity-100", "opacity-0"})
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

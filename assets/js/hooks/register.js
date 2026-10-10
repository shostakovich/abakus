// The register's comboboxes and edit row, as in YNAB.

// The server's lookup key, near enough for filtering: no emoji, spacing collapsed, lower case, "ß" as "ss".
const EMOJI = /[\p{So}\p{Extended_Pictographic}\p{Emoji_Modifier}\p{Regional_Indicator}‍︎️⃣]/gu
const lookupKey = (text) =>
  text.normalize("NFC").replace(EMOJI, " ").replace(/\s+/g, " ").trim().toLowerCase().replaceAll("ß", "ss")

// A payee or category picker: the list opens on focus, typing filters it, the arrows move, Enter and Tab take the
// highlighted option, Escape closes it. The options come from the <template> named in data-options, so a page
// holds them once. A pick goes to the server as "pick" ({side, field, value}), or with data-submit into the hidden
// input and the form is submitted by that button. A category's text is no form field: leaving without a pick
// puts the chosen one back.
export const Combobox = {
  mounted() {
    this.input = this.el.querySelector("[role=combobox]")
    this.menu = this.el.querySelector("[role=listbox]")
    // Empty while closed, so CSS hides it.
    this.menu.replaceChildren()
    this.input.addEventListener("focus", () => this.open())
    this.input.addEventListener("click", () => this.open())
    this.input.addEventListener("input", () => {
      this.typed = true
      this.isOpen ? this.filter(this.input.value) : this.open(true)
    })
    this.input.addEventListener("keydown", (event) => this.keydown(event))
    this.input.addEventListener("blur", () => this.leave())
    // Keeps the focus in the input while an option is clicked.
    this.menu.addEventListener("mousedown", (event) => event.preventDefault())
    this.menu.addEventListener("click", (event) => {
      const option = event.target.closest("[role=option]")
      if (option) this.pick(option)
    })
  },

  // The server changed the choice (a payee's last category, say): a focused input keeps its text unless shown anew.
  updated() {
    const label = this.el.dataset.label || ""
    if (this.input.value === label) this.typed = false
    if (this.typed || this.input.value === label) return
    this.input.value = label
    if (this.isOpen) this.filter("")
  },

  open(typing = false) {
    if (this.isOpen) return
    const template = document.getElementById(this.el.dataset.options)
    this.menu.replaceChildren(template.content.cloneNode(true))
    if (!this.el.dataset.split) this.menu.querySelectorAll("[data-split-only]").forEach((el) => el.remove())
    this.menu.querySelectorAll("[role=option]").forEach((option, index) => (option.id = `${this.menu.id}-${index}`))
    this.isOpen = true
    this.input.setAttribute("aria-expanded", "true")
    if (typing) {
      this.filter(this.input.value)
    } else {
      this.typed = false
      this.input.select()
      this.filter("")
    }
  },

  close() {
    if (!this.isOpen) return
    this.isOpen = false
    this.active = null
    this.menu.replaceChildren()
    this.input.setAttribute("aria-expanded", "false")
    this.input.removeAttribute("aria-activedescendant")
  },

  options() {
    return [...this.menu.querySelectorAll("[role=option]")].filter((option) => !option.hidden)
  },

  // Without a query everything shows and the chosen option is highlighted; with one the first match.
  filter(text) {
    const query = lookupKey(text)
    const options = [...this.menu.querySelectorAll("[role=option]:not([data-create])")]
    options.forEach((option) => (option.hidden = query !== "" && !option.dataset.key.includes(query)))
    this.menu.querySelectorAll("[role=group]").forEach((group) => {
      group.hidden = !group.querySelector("[role=option]:not([hidden])")
    })
    const create = this.menu.querySelector("[data-create]")
    if (create) {
      create.hidden = query === "" || options.some((option) => option.dataset.key === query)
      create.querySelector("span").textContent = text.trim()
    }
    const current = options.find((option) => option.dataset.value === this.el.dataset.value)
    const first = options.find((option) => !option.hidden) || (create && !create.hidden && create)
    this.highlight(query === "" ? current : first)
  },

  highlight(option) {
    this.active?.classList.remove("active")
    this.active = option || null
    if (!option) return this.input.removeAttribute("aria-activedescendant")
    option.classList.add("active")
    option.scrollIntoView({ block: "nearest" })
    this.input.setAttribute("aria-activedescendant", option.id)
  },

  keydown(event) {
    if (!this.isOpen) {
      if (event.key === "ArrowDown") {
        event.preventDefault()
        this.open()
      } else if (event.key === "Enter" && this.el.dataset.save) {
        // The category's text is no form field, so Enter saves by the button, which asks first where it must.
        event.preventDefault()
        document.getElementById(this.el.dataset.save)?.click()
      }
      return
    }
    const options = this.options()
    const index = options.indexOf(this.active)
    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp":
        event.preventDefault()
        this.highlight(options[Math.min(Math.max(index + (event.key === "ArrowDown" ? 1 : -1), 0), options.length - 1)])
        break
      case "Enter":
        if (this.active) {
          event.preventDefault()
          this.pick(this.active)
        }
        break
      case "Tab":
        if (this.active) this.pick(this.active)
        break
      case "Escape":
        // Closes only the list; the next Escape cancels the edit.
        event.preventDefault()
        event.stopPropagation()
        this.close()
        this.restore()
        break
    }
  },

  pick(option) {
    const create = option.hasAttribute("data-create")
    const label = create ? this.input.value.trim() : option.dataset.label
    const value = create ? `p:${label}` : option.dataset.value
    this.input.value = label
    this.typed = false
    this.el.dataset.value = value
    this.el.dataset.label = label
    this.close()
    if (this.el.dataset.submit) {
      this.el.querySelector("input[type=hidden]").value = value
      document.getElementById(this.el.dataset.submit).click()
    } else {
      this.pushEventTo(this.el, "pick", { side: this.el.dataset.side, field: this.el.dataset.field, value })
    }
  },

  leave() {
    this.close()
    this.restore()
  },

  // A category picker shows what is chosen, whatever was typed.
  restore() {
    if (this.el.dataset.field === "category" && !this.el.dataset.submit) this.input.value = this.el.dataset.label || ""
  },
}

// The edited row: the cursor goes into the cell that was clicked, its text selected.
export const EditRow = {
  mounted() {
    const input = document.getElementById(this.el.dataset.focus)
    if (!input) return
    input.focus()
    if (typeof input.select === "function" && input.type !== "date") input.select()
    this.el.scrollIntoView({ block: "nearest" })
  },
}

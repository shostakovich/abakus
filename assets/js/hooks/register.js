export const EditRow = {
  mounted() {
    // Only inside the row: Escape in a dialog or an open list above it closes just that.
    this.el.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && !event.defaultPrevented) this.pushEvent("cancel_edit", {})
    })
    // A typed or pasted sign goes to the sign button, as LiveView never patches the focused field to drop it.
    this.el.addEventListener("keydown", (event) => {
      if (event.metaKey || event.ctrlKey || event.altKey) return
      if (!["+", "-", "−"].includes(event.key) || !this.signButton(event.target)) return
      event.preventDefault()
      this.setSign(event.target, event.key)
    })
    this.el.addEventListener("input", (event) => {
      const typed = this.signButton(event.target) && event.target.value.match(/^\s*([+\-−])\s*/)
      if (!typed) return
      event.target.value = event.target.value.slice(typed[0].length)
      this.setSign(event.target, typed[1])
    })
    const input = document.getElementById(this.el.dataset.focus)
    if (!input) return
    input.focus({ preventScroll: true })
    if (typeof input.select === "function" && input.type !== "date") input.select()
    this.el.scrollIntoView({ block: "nearest" })
  },
  signButton(input) {
    return input.dataset.signButton && document.getElementById(input.dataset.signButton)
  },
  // Set at once, so a second sign typed before the server answers compares against the first.
  setSign(input, typed) {
    const button = this.signButton(input)
    const sign = typed === "+" ? "+" : "-"
    if (button.dataset.sign === sign) return
    button.click()
    button.dataset.sign = sign
  },
}

// Reconcile mode's bar sticks to the top, so the register's column header sticks below it.
export const StickyBar = {
  mounted() {
    this.observer = new ResizeObserver(() => this.place())
    this.observer.observe(this.el)
    this.place()
  },
  place() {
    const gap = parseFloat(getComputedStyle(this.el).marginBottom) || 0
    document.documentElement.style.setProperty("--reg-head-top", `${this.el.offsetHeight + gap}px`)
  },
  destroyed() {
    this.observer.disconnect()
    document.documentElement.style.removeProperty("--reg-head-top")
  },
}

// Watches the table and the phone list alike: the one hidden at this width never intersects.
// Observing anew after each load keeps tall screens filled.
export const LoadMore = {
  mounted() {
    this.observer = new IntersectionObserver(
      (entries) => {
        if (this.loading || !entries.some((entry) => entry.isIntersecting)) return
        this.loading = true
        this.pushEvent("load_more", {}).then(
          () => {
            this.loading = false
            this.observe()
          },
          // Offline: `reconnected` asks again.
          () => (this.loading = false),
        )
      },
      { rootMargin: "0px 0px 800px 0px" },
    )
    this.observe()
  },
  reconnected() {
    this.loading = false
    this.observe()
  },
  observe() {
    this.observer.unobserve(this.el)
    this.observer.observe(this.el)
  },
  destroyed() {
    this.observer.disconnect()
  },
}

const memoKey = "abakus:register-memo"

// The register's memo column, shown or hidden per device; the root layout applies the choice before paint.
export function toggleMemo() {
  const root = document.documentElement
  const hide = root.getAttribute("data-register-memo") !== "hidden"
  if (hide) root.setAttribute("data-register-memo", "hidden")
  else root.removeAttribute("data-register-memo")
  try {
    if (hide) localStorage.setItem(memoKey, "hidden")
    else localStorage.removeItem(memoKey)
  } catch (_) {}
}

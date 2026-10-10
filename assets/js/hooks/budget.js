// Months and inspector from the budget's width, as in YNAB 4 (1, 2 or 3 months, no selector): the inspector comes
// before a third month, and a month is only added while the category column keeps 15rem, so about 1200 px give
// 1 month and the inspector, 1600 px 2, 1920 px 3; narrower ones 1 month alone. The category column takes what the months leave, up to 16rem.
const MONTH = 296
const INSPECTOR = 304 // 18rem and the gap
const CATEGORY_MIN = 240
const CATEGORY_MAX = 256
const DESKTOP = 992

const clamp = (value, low, high) => Math.min(high, Math.max(low, value))

export function budgetFit(width, viewport) {
  const preferred = clamp(viewport * 0.17, 224, CATEGORY_MAX)
  const room = width - Math.max(preferred, CATEGORY_MIN)
  const inspector = viewport >= DESKTOP && room - INSPECTOR >= MONTH
  const months = inspector ? clamp(Math.floor((room - INSPECTOR) / MONTH), 1, 3) : 1
  const table = width - (inspector ? INSPECTOR : 0)
  const category = clamp(Math.floor(table - months * MONTH - 4), preferred, CATEGORY_MAX)
  const span = clamp(Math.floor((table - category - 140) / 34), 7, 12)
  return { months, inspector, span, category, month: Math.max(table - category, months * MONTH) / months }
}

// For the connect params, so the first render already shows what fits.
export function initialBudgetFit() {
  const budget = document.getElementById("budget")
  if (!budget) return undefined
  const { months, inspector, span } = budgetFit(budget.clientWidth, window.innerWidth)
  return { months, inspector, span }
}

const root = document.documentElement.style

// Tells the server what fits whenever that changes (it renders it as data-fit), sizes the columns and moves Enter to
// the next category.
export const BudgetLayout = {
  mounted() {
    this.observer = new ResizeObserver(() => this.layout())
    this.observer.observe(this.el)
    this.el.addEventListener("keydown", (event) => this.nextOnEnter(event))
    this.el.addEventListener("focusin", ({ target }) => target.matches(".app-assign") && target.select())
    this.layout()
  },

  destroyed() {
    this.observer.disconnect()
  },

  layout() {
    const fit = budgetFit(this.el.clientWidth, window.innerWidth)
    root.setProperty("--cat-w", `${fit.category}px`)
    root.setProperty("--month-w", `${fit.month}px`)
    if (this.el.dataset.fit !== [fit.months, fit.inspector, fit.span].join()) {
      this.pushEvent("fit", { months: fit.months, inspector: fit.inspector, span: fit.span })
    }
  },

  nextOnEnter(event) {
    const input = event.target
    if (event.key !== "Enter" || !input.matches(".app-assign")) return
    event.preventDefault()
    const month = input.getAttribute("phx-value-month")
    // Inputs in collapsed groups take no focus.
    const column = [...this.el.querySelectorAll(`.app-assign[phx-value-month="${month}"]`)].filter((i) => i.offsetParent)
    const next = column[column.indexOf(input) + 1]
    next ? next.focus() : input.blur()
  },
}

// Whole chips only: the trailing ones fold into "Filter" while the row is too short.
export const FilterChips = {
  mounted() {
    this.observer = new ResizeObserver(() => this.fit())
    this.observer.observe(this.el)
    this.fit()
  },

  updated() {
    this.fit()
  },

  destroyed() {
    this.observer.disconnect()
  },

  fit() {
    const chips = [...this.el.querySelectorAll(":scope > [data-chip]")]
    const items = [...this.el.querySelectorAll("[data-fold]")]
    const more = this.el.querySelector("#filters-more")
    chips.forEach((chip) => (chip.hidden = false))
    items.forEach((item) => (item.hidden = true))
    more.hidden = true

    for (let k = chips.length - 1; k > 0 && this.el.scrollWidth > this.el.clientWidth; k--) {
      more.hidden = false
      chips[k].hidden = true
      items[k].hidden = false
    }

    const folded = chips.some((chip) => chip.hidden && chip.getAttribute("aria-pressed") === "true")
    const toggle = more.querySelector(".dropdown-toggle")
    toggle.classList.toggle("btn-primary", folded)
    toggle.classList.toggle("btn-light", !folded)
  },
}

// A popover below its anchor (above it when there is no room), its right edge at the anchor's, kept on screen.
export const Popover = {
  mounted() {
    this.place()
    this.el.querySelector("select, input:not([type=radio]):not([type=hidden])")?.focus()
  },

  updated() {
    this.place()
  },

  place() {
    const anchor = document.getElementById(this.el.dataset.anchor)
    if (!anchor) return
    const box = anchor.getBoundingClientRect()
    const { offsetWidth: width, offsetHeight: height } = this.el
    const below = box.bottom + height + 8 <= window.innerHeight
    this.el.style.left = `${clamp(box.right - width, 8, window.innerWidth - width - 8)}px`
    this.el.style.top = `${below ? box.bottom + 6 : Math.max(8, box.top - height - 6)}px`
    this.el.style.visibility = "visible"
  },
}

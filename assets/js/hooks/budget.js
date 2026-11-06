import { refocusAmount } from "./refocus.js"

// Months by the budget's width, as in Actual: two from 760 px, three from 1110 px; below lg one month in a bar.
const TWO_MONTHS = 760
const THREE_MONTHS = 1110
const CATEGORY_MIN = 224
const CATEGORY_MAX = 320
const DESKTOP = 1024
const PHONE = 640
const AVAILABLE = 120
const STRIP_FRAME = 152 // the two arrows and two year labels
const STRIP_MONTH = 40

const clamp = (value, low, high) => Math.min(high, Math.max(low, value))

export function budgetFit(width, viewport) {
  if (viewport < DESKTOP) {
    // Phones show only Verfügbar beside the name; assigning moves into the panel.
    const category = viewport < PHONE ? width - AVAILABLE : clamp(width - 296, 200, 256)
    return { months: 1, compact: true, span: 7, category, month: width - category }
  }
  const months = width >= THREE_MONTHS ? 3 : width >= TWO_MONTHS ? 2 : 1
  const category = clamp(Math.floor(width * 0.22), CATEGORY_MIN, CATEGORY_MAX)
  const span = clamp(Math.floor((width - STRIP_FRAME) / STRIP_MONTH), 5, 12)
  return { months, compact: false, span, category, month: (width - category) / months }
}

const pushed = ({ months, span, compact }) => ({ months, span, compact })

// So the first render fits; navigating in the app connects before #budget exists, when only phones know their fit.
export function initialBudgetFit() {
  const budget = document.getElementById("budget")
  if (budget) return pushed(budgetFit(budget.clientWidth, window.innerWidth))
  if (window.innerWidth < DESKTOP) return pushed(budgetFit(window.innerWidth, window.innerWidth))
  return undefined
}

const root = document.documentElement.style

export const BudgetLayout = {
  mounted() {
    this.observer = new ResizeObserver(() => this.layout())
    this.observer.observe(this.el)
    this.el.addEventListener("keydown", (event) => this.nextOnEnter(event))
    // On the document: the phone's sheet lies outside the budget.
    this.onEscape = (event) => this.restoreOnEscape(event)
    document.addEventListener("keydown", this.onEscape)
    this.el.addEventListener("focusin", ({ target }) => target.matches(".app-assign") && target.select())
    this.handleEvent("refocus_amount", ({ id }) => refocusAmount(id, (active) => active.matches(".app-assign")))
    this.layout()
  },

  destroyed() {
    this.observer.disconnect()
    document.removeEventListener("keydown", this.onEscape)
    root.removeProperty("--cat-w")
    root.removeProperty("--month-w")
  },

  layout() {
    const fit = budgetFit(this.el.clientWidth, window.innerWidth)
    root.setProperty("--cat-w", `${fit.category}px`)
    root.setProperty("--month-w", `${fit.month}px`)
    const params = pushed(fit)
    if (this.el.dataset.fit !== [params.months, params.span, params.compact].join()) {
      this.pushEvent("fit", params)
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

  // Unchanged, Escape is left to the sheet, which closes.
  restoreOnEscape(event) {
    const input = event.target
    if (event.key !== "Escape" || !input.matches(".app-assign, #panel-assign")) return
    const saved = input.dataset.saved ?? ""
    if (input.value === saved && input.getAttribute("aria-invalid") !== "true") return
    event.preventDefault()
    event.stopPropagation()
    input.value = saved
    input.select()
    this.pushEvent("assign_cancel", {
      category: input.getAttribute("phx-value-category"),
      month: input.getAttribute("phx-value-month"),
    })
  },
}

const calculationKey = "abakus:budget-calculation"
const calculationShown = () => document.documentElement.getAttribute("data-budget-calculation") === "shown"

// Per device; the root layout applies the choice before paint.
export const CalculationToggle = {
  mounted() {
    this.el.addEventListener("click", () => this.toggle())
    this.el.setAttribute("aria-expanded", String(calculationShown()))
  },

  toggle() {
    const root = document.documentElement
    const show = !calculationShown()
    if (show) root.setAttribute("data-budget-calculation", "shown")
    else root.removeAttribute("data-budget-calculation")
    try {
      if (show) localStorage.setItem(calculationKey, "shown")
      else localStorage.removeItem(calculationKey)
    } catch (_) {}
    for (const toggle of document.querySelectorAll("[phx-hook=CalculationToggle]")) {
      toggle.setAttribute("aria-expanded", String(show))
    }
  },
}

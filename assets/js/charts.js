// Chart.js 4.5.1 UMD build; time axes are linear in days with German labels of their own, no date adapter.
import Chart from "../vendor/chart.umd.min.js"

const DAY = 86_400_000
export const MONTHS = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
const euroFormat = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR", maximumFractionDigits: 0 })
const numberFormat = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 1 })

// Days since 1970 for an ISO date like "2026-10-09", the x values of a time axis.
export const day = (iso) => Date.parse(iso) / DAY

const utc = (day) => new Date(day * DAY)

export const formatDay = (day) =>
  utc(day).toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "UTC" })

export const formatEuros = (euros) => euroFormat.format(euros)

export const formatAxisEuros = (euros) =>
  Math.abs(euros) >= 1000 ? `${numberFormat.format(euros / 1000)}\u00a0T€` : `${numberFormat.format(euros)}\u00a0€`

// A single day gets a day on either side, so that its point has room.
export function timeAxis(first, last, tickOptions = {}) {
  const single = first === last
  return {
    type: "linear",
    min: single ? first - 1 : first,
    max: single ? last + 1 : last,
    afterBuildTicks: (scale) => {
      scale.ticks = ticks(scale.min, scale.max, Math.max(3, Math.floor(scale.width / 56)))
    },
    ticks: { ...tickOptions, maxRotation: 0, callback: (_value, index, ticks) => ticks[index].label },
  }
}

function ticks(min, max, count) {
  if (max - min <= 62) {
    const step = [1, 2, 7, 14].find((days) => (max - min) / days <= count) ?? 14
    const days = []
    for (let value = Math.ceil(min); value <= max; value += step) {
      const date = utc(value)
      days.push({ value, label: `${date.getUTCDate()}. ${MONTHS[date.getUTCMonth()]}` })
    }
    return days
  }

  const start = utc(min), end = utc(max)
  const firstMonth = start.getUTCFullYear() * 12 + start.getUTCMonth()
  const months = end.getUTCFullYear() * 12 + end.getUTCMonth() - firstMonth
  const step = [1, 2, 3, 6, 12, 24, 60, 120].find((n) => months / n <= count) ?? 120
  const result = []
  for (let month = Math.ceil(firstMonth / step) * step; ; month += step) {
    const value = Date.UTC(Math.floor(month / 12), month % 12, 1) / DAY
    if (value > max) break
    if (value >= min) result.push({ value, label: month % 12 ? MONTHS[month % 12] : String(month / 12) })
  }
  return result
}

// `color` is a custom property such as "--color-chart-1" or any CSS colour, resolved for the current theme.
export function cssColor(el, color) {
  el.style.color = color.startsWith("--") ? `var(${color})` : color
  const resolved = getComputedStyle(el).color
  el.style.color = ""
  return rgba(resolved)
}

let pixel

// Chart.js cannot parse the computed oklch()/oklab() to lighten on hover; a painted pixel reads back as rgba().
function rgba(color) {
  pixel ??= document.createElement("canvas").getContext("2d", { willReadFrequently: true })
  pixel.clearRect(0, 0, 1, 1)
  pixel.fillStyle = color
  pixel.fillRect(0, 0, 1, 1)
  const [r, g, b, a] = pixel.getImageData(0, 0, 1, 1).data
  return `rgba(${r}, ${g}, ${b}, ${Math.round((a / 255) * 1000) / 1000})`
}

// A Setzkasten series such as "chart-1": fill for bars, areas and dots, line for lines and outlines.
export const series = (el, name) => ({ fill: cssColor(el, `--color-${name}-fill`), line: cssColor(el, `--color-${name}`) })

// The page's text colour at `percent` strength: axes and their labels at 70, grid lines at 10.
export const inkColor = (el, percent) =>
  cssColor(el, `color-mix(in oklab, var(--color-base-content) ${percent}%, transparent)`)

export const transparent = (el, color, alpha) =>
  cssColor(el, `color-mix(in oklab, ${color} ${alpha * 100}%, transparent)`)

export const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches

// Redraws on a theme change, by the device's colour scheme or data-theme on <html>.
export function chartHook(event, config) {
  return {
    mounted() {
      this.handleEvent(event, (data) => this.draw(data))
      this.redraw = () => this.data && this.draw(this.data)
      this.scheme = matchMedia("(prefers-color-scheme: dark)")
      this.scheme.addEventListener("change", this.redraw)
      this.theme = new MutationObserver(this.redraw)
      this.theme.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] })
    },

    destroyed() {
      this.scheme.removeEventListener("change", this.redraw)
      this.theme.disconnect()
      this.chart?.destroy()
    },

    draw(data) {
      this.data = data
      const chart = config(data, this.el)

      if (!chart) {
        this.chart?.destroy()
        this.chart = null
      } else if (this.chart) {
        this.chart.data = chart.data
        this.chart.options = chart.options
        this.chart.update()
      } else {
        this.chart = new Chart(this.el.querySelector("canvas"), chart)
      }
    },
  }
}

import { chartHook, cssColor, inkColor, day, series, formatDay, reducedMotion, timeAxis, transparent } from "../charts.js"

const TRADES = { buy: "Kauf", inbound_delivery: "Einlieferung", sell: "Verkauf", outbound_delivery: "Auslieferung" }
const PURCHASES = ["buy", "inbound_delivery"]

const priceFormat = new Intl.NumberFormat("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 4 })
const axisFormat = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 2 })
const sharesFormat = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 8 })

// Prices and shares come × 10⁸.
const unscaled = (value) => value / 100_000_000

// A security's prices over the period, its purchases and sales as dots at their price per share;
// the security page pushes them with the currency they are in. Nothing without prices.
export const PriceChart = chartHook("price-chart", ({ currency, dates, prices, trades }, el) => {
  if (dates.length === 0) return null

  const color = (name) => cssColor(el, name)
  // The price in series 1; purchases and sales in the ink of gains and losses.
  const primary = series(el, "chart-1").line
  const [success, danger, background] = ["--color-success-ink", "--color-error-ink", "--color-base-100"].map(color)
  const [muted, grid] = [inkColor(el, 70), inkColor(el, 10)]
  const days = dates.map(day)
  const last = days.length - 1
  // A trade may lie before the first price, or after the last one.
  const span = [...days, ...trades.map((trade) => day(trade.date))]
  const font = { family: getComputedStyle(el).fontFamily, size: 12 }
  const compact = el.clientWidth < 576
  const price = (value) => `${priceFormat.format(value)}\u00a0${currency}`
  const dots = (purchases) =>
    trades
      .filter((trade) => PURCHASES.includes(trade.type) === purchases)
      .map((trade) => ({ x: day(trade.date), y: unscaled(trade.price), trade }))
  const tradeDots = {
    showLine: false,
    clip: false,
    pointRadius: compact ? 4 : 4.5,
    pointHoverRadius: compact ? 5 : 6,
    pointBorderColor: background,
    pointBorderWidth: 1.5,
  }

  return {
    type: "line",
    data: {
      datasets: [
        {
          label: "Kurs",
          // Drawn below the trades, which would otherwise disappear under the line.
          order: 1,
          data: prices.map((value, i) => ({ x: days[i], y: unscaled(value) })),
          borderColor: primary,
          borderWidth: compact ? 1.75 : 2.5,
          backgroundColor: transparent(el, "var(--color-chart-1-fill)", 0.14),
          fill: "start",
          clip: false,
          pointRadius: (context) => (context.dataIndex === last ? 4 : 0),
          pointHoverRadius: 4,
          pointBackgroundColor: primary,
          pointBorderColor: background,
          pointBorderWidth: 2,
        },
        {
          ...tradeDots,
          label: "Käufe",
          data: dots(true),
          pointBackgroundColor: success,
        },
        {
          ...tradeDots,
          label: "Verkäufe",
          data: dots(false),
          pointBackgroundColor: danger,
        },
      ],
    },
    options: {
      maintainAspectRatio: false,
      animation: reducedMotion() ? false : { duration: 300 },
      interaction: { mode: "nearest", axis: "x", intersect: false },
      layout: { padding: { top: 6, right: 6 } },
      scales: {
        x: {
          ...timeAxis(Math.min(...span), Math.max(...span), { color: muted, font }),
          grid: { display: false },
          border: { display: false },
        },
        y: {
          grid: { color: grid },
          border: { display: false, dash: [3, 4] },
          ticks: { maxTicksLimit: 6, color: muted, font, callback: (value) => `${axisFormat.format(value)}\u00a0${currency}` },
        },
      },
      plugins: {
        legend: { display: false },
        tooltip: {
          itemSort: (a, b) => a.datasetIndex - b.datasetIndex,
          callbacks: {
            title: ([item]) => formatDay(item.parsed.x),
            label: ({ raw: { trade }, parsed }) =>
              trade
                ? ` ${TRADES[trade.type]}: ${sharesFormat.format(unscaled(trade.shares))} Stück à ${price(parsed.y)}`
                : ` Kurs: ${price(parsed.y)}`,
          },
        },
      },
    },
  }
})

import { MONTHS, chartHook, inkColor, formatEuros, reducedMotion, series, transparent } from "../charts.js"

function niceAxis(peak) {
  if (peak <= 0) return { step: 1, max: 5 }
  const power = 10 ** Math.floor(Math.log10(peak / 5))
  const steps = [0.1, 1, 10].flatMap((p) => [1, 2, 2.5, 5].map((n) => n * p * power))
  const fits = steps
    .map((step) => ({ step, max: Math.ceil(peak / step) * step }))
    .filter(({ step, max }) => max / step >= 3 && max / step <= 5)
  return fits.reduce((best, s) => (s.max < best.max || (s.max === best.max && s.step > best.step) ? s : best))
}

// The decimal places of a step such as 0.25.
const places = (step) => {
  const [, fraction = ""] = String(Number(step.toPrecision(6))).split(".")
  return fraction.length
}

// Tick labels with the unit and as many decimals as the step needs: "0,25 €", "2,5 T€".
function euroTicks(step) {
  const scale = step >= 1000 ? 1000 : 1
  const digits = places(step / scale)
  const format = new Intl.NumberFormat("de-DE", { minimumFractionDigits: digits, maximumFractionDigits: digits })
  const unit = scale === 1000 ? "\u00a0T€" : "\u00a0€"
  return (euros) => `${format.format(euros / scale)}${unit}`
}

function barOptions(el, { step, max, stacked = false, tooltip }) {
  const [muted, grid] = [inkColor(el, 70), inkColor(el, 10)]
  const font = { family: getComputedStyle(el).fontFamily, size: 12 }

  return {
    maintainAspectRatio: false,
    animation: reducedMotion() ? false : { duration: 300 },
    interaction: { mode: "index", intersect: false },
    layout: { padding: { top: 6, bottom: 0 } },
    scales: {
      x: {
        stacked,
        grid: { display: false },
        border: { display: true, color: muted },
        ticks: { color: muted, font, maxRotation: 0, autoSkip: false },
      },
      y: {
        stacked,
        min: 0,
        max,
        grid: { color: grid, drawTicks: false },
        border: { display: false, dash: [3, 4] },
        ticks: { stepSize: step, padding: 6, color: muted, font, callback: euroTicks(step) },
      },
    },
    plugins: {
      legend: { display: false },
      tooltip: {
        ...tooltip,
        callbacks: {
          label: (item) => ` ${item.dataset.label}: ${formatEuros(item.parsed.y)}`,
          ...tooltip.callbacks,
        },
      },
    },
  }
}

// This year in series 1, the years before in 2 and 8, as the page names them.
export const DividendChart = chartHook("dividend-chart", ({ years }, el) => {
  const compact = el.clientWidth < 576
  const euros = years.map(({ amounts }) => amounts.map((cents) => cents / 100))
  const { step, max } = niceAxis(Math.max(0, ...euros.flat()))

  return {
    type: "bar",
    data: {
      labels: compact ? MONTHS.map((month) => month[0]) : MONTHS,
      datasets: years.map(({ year, colour }, i) => ({
        label: String(year),
        data: euros[i],
        backgroundColor: series(el, colour).fill,
        borderColor: series(el, colour).line,
        borderWidth: 1,
        borderRadius: { topLeft: 3, topRight: 3 },
        borderSkipped: "start",
        categoryPercentage: compact ? 0.94 : 0.86,
        barPercentage: compact ? 1 : 0.9,
      })),
    },
    options: barOptions(el, {
      step,
      max,
      tooltip: { callbacks: { title: ([item]) => MONTHS[item.dataIndex] } },
    }),
  }
})

export const UpcomingDividendChart = chartHook("upcoming-dividend-chart", ({ months }, el) => {
  // Announced in series 1, the forecast in its fill mixed lighter, both outlined in its line.
  const now = series(el, "chart-1")
  const compact = el.clientWidth < 360
  const announced = months.map((month) => month.announced / 100)
  const forecast = months.map((month) => month.forecast / 100)
  const { step, max } = niceAxis(Math.max(0, ...announced.map((euros, i) => euros + forecast[i])))
  const bar = { borderSkipped: "start", categoryPercentage: compact ? 0.8 : 0.7, barPercentage: 1 }
  const top = { topLeft: 3, topRight: 3 }

  return {
    type: "bar",
    data: {
      labels: months.map(({ label, year }) => {
        const text = compact ? label[0] : label
        return year ? [text, compact ? `’${String(year).slice(2)}` : String(year)] : text
      }),
      datasets: [
        { ...bar, label: "angekündigt", data: announced, backgroundColor: now.fill,
          borderColor: now.line, borderWidth: 1,
          borderRadius: ({ dataIndex }) => (forecast[dataIndex] > 0 ? 0 : top) },
        {
          ...bar,
          label: "Prognose",
          data: forecast,
          // Matches the forecast key in dividends_live.ex (bg-chart-1-fill/35).
          backgroundColor: transparent(el, "var(--color-chart-1-fill)", 0.35),
          borderColor: now.line,
          borderWidth: 1,
          borderRadius: top,
        },
      ],
    },
    options: barOptions(el, {
      step,
      max,
      stacked: true,
      tooltip: {
        filter: (item) => item.parsed.y > 0,
        callbacks: { title: ([item]) => months[item.dataIndex].title },
      },
    }),
  }
})

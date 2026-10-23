import { chartHook, cssColor, inkColor, day, series, formatAxisEuros, formatDay, formatEuros, reducedMotion, timeAxis, transparent } from "../charts.js"

// Amounts in cents; no invested capital when net worth is the budget's, no benchmark without a pick.
const chart = chartHook("net-worth-chart", (data, el) => {
  const { dates, net_worth, invested_capital, benchmark, benchmark_name, benchmark_shown } = data
  const [netWorth, invested, mark] = ["chart-1", "chart-8", "chart-2"].map((name) => series(el, name))
  const background = cssColor(el, "--color-base-100")
  const [line, secondary, mustard] = [netWorth.line, invested.line, mark.line]
  const [muted, grid] = [inkColor(el, 70), inkColor(el, 10)]
  const days = dates.map(day)
  const points = (cents) => cents.map((amount, i) => ({ x: days[i], y: amount === null ? null : amount / 100 }))
  const last = days.length - 1
  const font = { family: getComputedStyle(el).fontFamily, size: 12 }
  const compact = el.clientWidth < 576

  return {
    type: "line",
    data: {
      datasets: [
        {
          label: "Vermögen",
          order: 0,
          data: points(net_worth),
          borderColor: line,
          borderWidth: compact ? 2.25 : 2.5,
          backgroundColor: transparent(el, "var(--color-chart-1-fill)", 0.14),
          fill: "start",
          clip: false,
          pointRadius: (context) => (context.dataIndex === last ? 4 : 0),
          pointHoverRadius: 4,
          pointBackgroundColor: line,
          pointBorderColor: background,
          pointBorderWidth: 2,
        },
        ...(invested_capital ? [{
          label: "Investiert",
          order: 2,
          data: points(invested_capital),
          borderColor: secondary,
          borderWidth: compact ? 1.5 : 1.75,
          borderDash: [5, 4],
          stepped: true,
          pointRadius: 0,
          pointHoverRadius: 4,
          pointBackgroundColor: secondary,
        }] : []),
        ...(benchmark ? [{
          label: benchmark_name,
          order: 1,
          data: points(benchmark),
          hidden: !benchmark_shown,
          borderColor: mustard,
          borderWidth: 1.5,
          borderJoinStyle: "round",
          borderCapStyle: "round",
          clip: false,
          pointRadius: (context) => (context.dataIndex === last ? 3 : 0),
          pointBorderColor: background,
          pointBorderWidth: 1.5,
          pointHoverRadius: 3,
          pointBackgroundColor: mustard,
        }] : []),
      ],
    },
    options: {
      maintainAspectRatio: false,
      animation: reducedMotion() ? false : { duration: 300 },
      interaction: { mode: "index", intersect: false },
      layout: { padding: { top: 6, right: 6 } },
      scales: {
        x: {
          ...timeAxis(days[0], days[last], { color: muted, font }),
          grid: { display: false },
          border: { display: false },
        },
        y: {
          grid: { color: grid },
          border: { display: false, dash: [3, 4] },
          ticks: { maxTicksLimit: compact ? 6 : 7, color: muted, font, callback: formatAxisEuros },
        },
      },
      plugins: {
        // All areas first, so that the net worth area does not tint the lines under it.
        filler: { drawTime: "beforeDatasetsDraw" },
        legend: { display: false },
        tooltip: {
          filter: (item) => item.parsed.y !== null,
          itemSort: (a, b) => a.datasetIndex - b.datasetIndex,
          callbacks: {
            title: ([item]) => formatDay(item.parsed.x),
            label: (item) => ` ${item.dataset.label}: ${formatEuros(item.parsed.y)}`,
          },
        },
      },
    },
  }
})

// Shows or hides the benchmark's line when the „Benchmark“ button is pressed (benchmark.ex).
export const NetWorthChart = {
  ...chart,
  mounted() {
    chart.mounted.call(this)
    this.handleEvent("benchmark", ({ shown }) => this.data && this.draw({ ...this.data, benchmark_shown: shown }))
  },
}

// Whether this device shows the benchmark on the overview and the performance screen: hidden unless
// shown here before. Every page sends the choice when it connects, so that its first render has it,
// and keeps it when the server says it changed (benchmark.ex).
const KEY = "abakus:benchmark"

// The choice made on this page, for a browser that keeps none, e.g. with storage blocked.
let choice = null

export const benchmarkChoice = () => {
  if (choice) return choice
  try { return localStorage.getItem(KEY) } catch { return null }
}

window.addEventListener("phx:benchmark", (e) => {
  choice = e.detail.shown ? "shown" : "hidden"
  try { localStorage.setItem(KEY, choice) } catch {}
})

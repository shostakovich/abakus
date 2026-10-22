// Per device, hidden unless shown here before; each page sends it on connect so its first render has it (benchmark.ex).
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

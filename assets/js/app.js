import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks as colocatedHooks } from "phoenix-colocated/abakus"
import { hooks as setzkastenHooks } from "phoenix-colocated/setzkasten"

import { benchmarkChoice } from "./benchmark.js"
import { BudgetLayout, CalculationToggle, initialBudgetFit, RenameField } from "./hooks/budget.js"
import { DividendChart, UpcomingDividendChart } from "./hooks/dividend_chart.js"
import { NetWorthChart } from "./hooks/net_worth_chart.js"
import { PasskeyLogin, PasskeyRegister } from "./hooks/passkey.js"
import { PriceChart } from "./hooks/price_chart.js"
import { EditRow, LoadMore, StickyBar, toggleMemo } from "./hooks/register.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const appHooks = {
  BudgetLayout,
  CalculationToggle,
  DividendChart,
  EditRow,
  LoadMore,
  NetWorthChart,
  PasskeyLogin,
  PasskeyRegister,
  PriceChart,
  RenameField,
  StickyBar,
  UpcomingDividendChart,
}

window.addEventListener("abakus:toggle-memo", toggleMemo)

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({ _csrf_token: csrfToken, fit: initialBudgetFit(), benchmark: benchmarkChoice() }),
  hooks: { ...colocatedHooks, ...setzkastenHooks, ...appHooks },
})

liveSocket.connect()
window.liveSocket = liveSocket

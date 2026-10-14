import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks as colocatedHooks } from "phoenix-colocated/abakus"
import { hooks as setzkastenHooks } from "phoenix-colocated/setzkasten"

import { BudgetLayout, initialBudgetFit } from "./hooks/budget.js"
import { PasskeyLogin, PasskeyRegister } from "./hooks/passkey.js"
import { EditRow } from "./hooks/register.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const appHooks = { BudgetLayout, EditRow, PasskeyLogin, PasskeyRegister }

// The user's own date, so the current month turns over at their midnight.
const today = () => {
  const date = new Date()
  const pad = (number) => String(number).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({ _csrf_token: csrfToken, today: today(), fit: initialBudgetFit() }),
  hooks: { ...colocatedHooks, ...setzkastenHooks, ...appHooks },
})

liveSocket.connect()
window.liveSocket = liveSocket

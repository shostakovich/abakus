import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

import { BudgetLayout, FilterChips, initialBudgetFit } from "./hooks/budget.js"
import { PasskeyLogin, PasskeyRegister } from "./hooks/passkey.js"
import { SideToggle } from "./hooks/sidebar.js"
import { ThemeSwitch } from "./hooks/theme.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// The user's own date, so the current month turns over at their midnight.
const today = () => {
  const date = new Date()
  const pad = (number) => String(number).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({ _csrf_token: csrfToken, today: today(), fit: initialBudgetFit() }),
  hooks: { BudgetLayout, FilterChips, PasskeyLogin, PasskeyRegister, SideToggle, ThemeSwitch },
})

liveSocket.connect()
window.liveSocket = liveSocket

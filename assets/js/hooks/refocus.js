// Back to a refused amount, unless focus has moved on to something `stays` does not accept.
export function refocusAmount(id, stays) {
  const input = document.getElementById(id)
  const active = document.activeElement
  if (!input || !input.getClientRects().length) return
  if (active && active !== document.body && active !== input && !stays(active)) return
  input.focus()
  input.setSelectionRange(input.value.length, input.value.length)
}

// The edited row, as in YNAB: the cursor goes into the cell that was clicked, its text selected.
export const EditRow = {
  mounted() {
    // Only inside the row: Escape in a dialog or an open list above it closes just that.
    this.el.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && !event.defaultPrevented) this.pushEvent("cancel_edit", {})
    })
    const input = document.getElementById(this.el.dataset.focus)
    if (!input) return
    input.focus()
    if (typeof input.select === "function" && input.type !== "date") input.select()
    this.el.scrollIntoView({ block: "nearest" })
  },
}

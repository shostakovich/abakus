// Collapses the sidebar to an icon rail and back, remembered per device; the inline script in the root layout
// applies the stored state before the first paint.
const root = document.documentElement

export const SideToggle = {
  mounted() {
    this.label()
    this.el.addEventListener("click", () => {
      const mini = root.classList.toggle("app-side-mini")
      try { localStorage.setItem("side", mini ? "mini" : "full") } catch {}
      this.label()
    })
  },

  label() {
    const text = root.classList.contains("app-side-mini") ? "Seitenleiste ausklappen" : "Seitenleiste einklappen"
    this.el.title = text
    this.el.setAttribute("aria-label", text)
  },
}

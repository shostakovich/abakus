// "light" and "dark" set data-bs-theme; "auto" removes it and felt-css follows the device.
// The inline script in the root layout applies the stored choice before the first paint.
export const ThemeSwitch = {
  mounted() {
    const root = document.documentElement
    const current = root.dataset.bsTheme || "auto"
    this.el.querySelector(`input[value="${current}"]`).checked = true

    this.el.addEventListener("change", ({ target }) => {
      if (target.value === "auto") delete root.dataset.bsTheme
      else root.dataset.bsTheme = target.value
      try { localStorage.setItem("theme", target.value) } catch {}
    })
  },
}

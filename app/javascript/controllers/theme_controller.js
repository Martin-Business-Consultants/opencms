import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["lightButton", "darkButton", "autoButton"]

  connect() {
    this.#applyStoredTheme()
  }

  setLight() {
    this.#theme = "light"
  }

  setDark() {
    this.#theme = "dark"
  }

  setAuto() {
    this.#theme = "auto"
  }

  toggle() {
    this.#theme = this.#isDark ? "light" : "dark"
  }

  get #isDark() {
    const theme = document.documentElement.getAttribute("data-theme")
    return theme ? theme === "dark" : window.matchMedia?.("(prefers-color-scheme: dark)")?.matches
  }

  // A person's own choice, else the install's default. Stored as "appearance"
  // ("system" for auto), the key earlier versions of the admin used, so
  // existing choices carry over.
  get #storedTheme() {
    const stored = localStorage.getItem("appearance")
    if (stored === "system") return "auto"
    return stored || this.#defaultTheme
  }

  get #defaultTheme() {
    const theme = document.documentElement.dataset.defaultTheme
    return theme === "light" || theme === "dark" ? theme : "auto"
  }

  set #theme(theme) {
    localStorage.setItem("appearance", theme === "auto" ? "system" : theme)
    this.#apply(theme)
  }

  #apply(theme) {

    const currentTheme = document.documentElement.getAttribute("data-theme") || "auto"
    const hasChanged = currentTheme !== theme

    const prefersReducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    const animate = hasChanged && !prefersReducedMotion

    const applyTheme = () => {
      if (theme === "auto") {
        document.documentElement.removeAttribute("data-theme")
      } else {
        document.documentElement.setAttribute("data-theme", theme)
      }

      this.#updateButtons()
    }

    if (animate && document.startViewTransition) {
      document.startViewTransition(applyTheme)
    } else {
      applyTheme()
    }
  }

  // Applies without saving, so the install's default keeps working until someone chooses.
  #applyStoredTheme() {
    this.#apply(this.#storedTheme)
  }

  #updateButtons() {
    const storedTheme = this.#storedTheme

    if (this.hasLightButtonTarget) { this.lightButtonTarget.checked = (storedTheme === "light") }
    if (this.hasDarkButtonTarget)  { this.darkButtonTarget.checked  = (storedTheme === "dark") }
    if (this.hasAutoButtonTarget)  { this.autoButtonTarget.checked  = (storedTheme !== "light" && storedTheme !== "dark") }
  }
}

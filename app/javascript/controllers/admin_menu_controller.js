import { Controller } from "@hotwired/stimulus"

// The admin menu's two states, both on <html> so CSS can style everything
// from one place: data-menu="folded" (icons only, remembered in localStorage
// and applied before paint by layouts/_menu_preference) and data-menu-open
// (the drawer on narrow screens, closed again on every visit).
export default class extends Controller {
  static targets = [ "foldToggle", "drawerToggle" ]

  connect() {
    this.closeDrawer = this.closeDrawer.bind(this)
    this.placeFlyout = this.placeFlyout.bind(this)
    this.replaceFlyout = this.replaceFlyout.bind(this)
    document.addEventListener("turbo:before-visit", this.closeDrawer)
    this.#menu?.addEventListener("mouseover", this.placeFlyout)
    this.#menu?.addEventListener("focusin", this.placeFlyout)
    this.#menu?.addEventListener("scroll", this.replaceFlyout, { passive: true })
    this.#sync()
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.closeDrawer)
    this.#menu?.removeEventListener("mouseover", this.placeFlyout)
    this.#menu?.removeEventListener("focusin", this.placeFlyout)
    this.#menu?.removeEventListener("scroll", this.replaceFlyout)
  }

  // The menu scrolls on its own, so fly-outs are fixed (a scrolling box would
  // clip them) and need placing: level with their item, shifted up just
  // enough to stay in the window (Settings, at the bottom, opens upward).
  placeFlyout(event) {
    const item = event.target.closest(".admin-menu__item")
    const flyout = item?.querySelector(":scope > .admin-menu__submenu")
    if (!flyout) return

    const { top, bottom } = item.getBoundingClientRect()
    flyout.style.setProperty("--flyout-top", `${top}px`)
    requestAnimationFrame(() => {
      // Too tall to open downward: open upward, ending level with the item.
      if (top + flyout.offsetHeight > window.innerHeight) {
        const bar = this.#menu.getBoundingClientRect().top
        flyout.style.setProperty("--flyout-top", `${Math.max(bar, bottom - flyout.offsetHeight)}px`)
      }
    })
  }

  // Scrolling the menu moves the hovered item; keep its fly-out beside it.
  replaceFlyout() {
    const item = this.#menu.querySelector(".admin-menu__item:is(:hover, :focus-within)")
    if (item) this.placeFlyout({ target: item })
  }

  toggleFold() {
    const folded = document.documentElement.dataset.menu !== "folded"
    if (folded) {
      document.documentElement.dataset.menu = "folded"
    } else {
      delete document.documentElement.dataset.menu
    }
    try { localStorage.setItem("admin-menu", folded ? "folded" : "open") } catch (error) {}
    this.#sync()
  }

  toggleDrawer() {
    document.documentElement.toggleAttribute("data-menu-open")
    this.#sync()
  }

  closeDrawer() {
    document.documentElement.removeAttribute("data-menu-open")
    this.#sync()
  }

  get #menu() {
    return document.getElementById("admin-menu")
  }

  #sync() {
    const root = document.documentElement
    if (this.hasFoldToggleTarget) this.foldToggleTarget.setAttribute("aria-pressed", root.dataset.menu === "folded")
    if (this.hasDrawerToggleTarget) this.drawerToggleTarget.setAttribute("aria-expanded", root.hasAttribute("data-menu-open"))
  }
}

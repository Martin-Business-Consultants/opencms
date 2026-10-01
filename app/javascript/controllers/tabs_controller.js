import { Controller } from "@hotwired/stimulus"

// Tabs over panels (an editor's Edit and JSON): each tab and its panel share
// a data-tab name. The chosen one is kept in the address's #hash, so a link
// or a reload lands on it. A lazy frame in a panel loads when the panel is
// shown: Turbo waits for a lazy frame to scroll into view, and doesn't see
// one that was hidden come out.
export default class extends Controller {
  static targets = [ "tab", "panel" ]

  connect() {
    const wanted = window.location.hash.slice(1)
    const names = this.tabTargets.map(tab => tab.dataset.tab)
    this.#show(names.includes(wanted) ? wanted : names[0], { remember: false })
  }

  select(event) {
    event.preventDefault()
    this.#show(event.currentTarget.dataset.tab)
  }

  #show(name, { remember = true } = {}) {
    this.tabTargets.forEach(tab => tab.setAttribute("aria-selected", tab.dataset.tab === name))
    this.panelTargets.forEach(panel => {
      panel.hidden = panel.dataset.tab !== name
      if (!panel.hidden) panel.querySelectorAll("turbo-frame[loading=lazy]").forEach(frame => { frame.loading = "eager" })
    })
    if (remember) history.replaceState(history.state, "", `#${name}`)
  }
}

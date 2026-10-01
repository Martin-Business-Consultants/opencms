import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"
import { nextFrame } from "helpers/timing_helpers"

// Every key the app answers to, vim style, in one place (on <body>). Letters act outside
// inputs and open dialogs; ⌘/Ctrl+Enter saves from anywhere in a form.
//
// - j / k, g g / G walk the page's items (anything marked data-filter-target="item"),
//   Enter or o opens the one you're on, Esc drops it
// - a chord starting with g goes somewhere: any element declaring data-keys="g c"
// - every other key clicks the visible element declaring it (data-keys="e"), or focuses it
//   (data-keys-focus). One inside the current item wins over the page's own, so e and d
//   act on the row you're on
// - on the Work board, h / l and j / k drive Fizzy's column navigation and H / L move the
//   card a column, posting to the same drop endpoint a drag would
//
// The ? sheet (layouts/shared/_shortcuts) lists them all. Esc with nothing selected goes up a
// level (<link rel="up">) or back.

const ITEM = "[data-filter-target~='item'], [data-keyboard-item]"
const TYPING = "input, textarea, select, [contenteditable], lexxy-editor"
const OPENER = ":is(a[href], button):not(.row-action):not([data-keys])"
const CHORD_TIMEOUT = 1500
const MOD = /Mac|iPhone|iPad/.test(navigator.platform) ? "meta" : "ctrl"
const BOARD_ARROWS = { j: "ArrowDown", k: "ArrowUp", h: "ArrowLeft", l: "ArrowRight" }

export default class extends Controller {
  connect() {
    this.keydown = this.keydown.bind(this)
    this.focusin = this.focusin.bind(this)
    document.addEventListener("keydown", this.keydown)
    document.addEventListener("focusin", this.focusin)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keydown)
    document.removeEventListener("focusin", this.focusin)
  }

  focusin({ target }) {
    if (this.current && !this.current.contains(target)) this.#clear()
  }

  // The item j / k landed on. A Turbo visit swaps the body out from under it (a morph keeps it).
  get current() {
    return this.selected?.isConnected ? this.selected : null
  }

  set current(item) {
    this.selected = item
  }

  keydown(event) {
    if (event.defaultPrevented || event.isComposing) return
    const key = describe(event)

    if (key === `${MOD}+enter`) return this.#save(event)
    if (event.target.closest?.(TYPING) || event.target.closest?.("dialog[open]") || document.querySelector("dialog:modal")) return

    if (this.pending) {
      const chord = `${this.pending} ${key}`
      this.pending = null
      if (chord === "g g") return this.#select(this.#items()[0], event)
      return this.#trigger(chord, event)
    }
    if (key === "g") return this.#startChord(event)

    if (this.#board && this.#boardKey(key, event)) return

    switch (key) {
      case "j": return this.#step(1, event)
      case "k": return this.#step(-1, event)
      case "G": return this.#select(this.#items().at(-1), event)
      case "enter":
      case "o":
        if (this.#open(event)) return
        break
      case "esc":
        if (this.current) return this.#clear(event)
        if (this.#trigger(key, event)) return
        return this.#up(event)
    }
    this.#trigger(key, event)
  }

  // Esc with nothing selected: the page one level up (<link rel="up">, from parent_page), or
  // back in history.
  #up(event) {
    const up = document.querySelector("link[rel=up]")?.href
    if (up) {
      event.preventDefault()
      window.Turbo ? window.Turbo.visit(up) : (location.href = up)
    } else if (history.length > 1 && location.pathname !== "/") {
      event.preventDefault()
      history.back()
    }
  }

  // Chords

  #startChord(event) {
    event.preventDefault()
    this.pending = "g"
    clearTimeout(this.chordTimer)
    this.chordTimer = setTimeout(() => { this.pending = null }, CHORD_TIMEOUT)
  }

  // Declared keys

  #trigger(key, event) {
    const declared = Array.from(document.querySelectorAll("[data-keys]")).filter(element => declares(element, key) && usable(element))
    const element = declared.find(candidate => this.current?.contains(candidate)) || declared.find(candidate => !candidate.closest(ITEM))
    if (!element) return false

    event.preventDefault()
    if (element.hasAttribute("data-keys-focus")) {
      element.focus()
      element.select?.()
    } else {
      element.click()
    }
    return true
  }

  #save(event) {
    const form = event.target.closest?.("form") || document.activeElement?.closest("form")
    if (!form) return

    event.preventDefault()
    form.requestSubmit()
  }

  // Items

  #items() {
    return Array.from(document.querySelectorAll(ITEM)).filter(usable)
  }

  #step(delta, event) {
    const items = this.#items()
    if (!items.length) return

    let index = items.indexOf(this.current)
    if (index < 0) index = items.findIndex(item => item.contains(document.activeElement))
    index = index < 0 ? (delta > 0 ? 0 : items.length - 1) : Math.min(Math.max(index + delta, 0), items.length - 1)
    this.#select(items[index], event)
  }

  #select(item, event) {
    if (!item) return

    event?.preventDefault()
    this.#clear()
    this.current = item
    item.setAttribute("data-keyboard-current", "")
    if (!item.hasAttribute("tabindex")) item.tabIndex = -1
    item.focus({ preventScroll: true })
    item.scrollIntoView({ block: "nearest" })
  }

  #clear(event) {
    event?.preventDefault()
    if (this.current) {
      this.current.removeAttribute("data-keyboard-current")
      if (this.current === document.activeElement) this.current.blur()
    }
    this.current = null
  }

  #open(event) {
    const item = this.current
    if (!item?.isConnected) return false
    if (document.activeElement !== item && item.contains(document.activeElement)) return false

    const opener = item.matches(OPENER) ? item : item.querySelector(OPENER)
    if (!opener) return false

    event.preventDefault()
    opener.click()
    return true
  }

  // Board

  get #board() {
    return document.querySelector(".card-columns")
  }

  #boardKey(key, event) {
    if (BOARD_ARROWS[key]) {
      this.#relay(BOARD_ARROWS[key], event)
      return true
    }
    if (key === "H" || key === "L") {
      this.#moveCard(key === "L" ? 1 : -1, event)
      return true
    }
    return false
  }

  // Fizzy's navigable lists listen for arrow keys on the board, so hand them one.
  async #relay(arrow, event) {
    event.preventDefault()
    const board = this.#board
    if (!board.contains(document.activeElement)) {
      (board.querySelector("section.cards[aria-selected]") || board.querySelector("section.cards"))?.focus()
      await nextFrame()
      await nextFrame()
    }
    const target = board.contains(document.activeElement) ? document.activeElement : board
    target.dispatchEvent(new KeyboardEvent("keydown", { key: arrow, bubbles: true, cancelable: true }))
  }

  async #moveCard(delta, event) {
    event.preventDefault()
    const board = this.#board
    // The selected card, the focused one, or the one just moved (redrawn cards lose selection).
    const card = board.querySelector("section.cards[aria-selected] .card[aria-selected]") || document.activeElement?.closest(".card") ||
      (this.movedId && board.querySelector(`.card[data-id="${this.movedId}"]`))
    if (!card) return

    const columns = Array.from(board.querySelectorAll("section.cards"))
    const from = card.closest("section.cards")
    const to = columns[columns.indexOf(from) + delta]
    if (!to) return

    const id = card.dataset.id
    adjustCount(from, -1)
    adjustCount(to, 1)
    to.querySelector("[data-drag-drop-item-container]")?.prepend(card)
    this.movedId = id
    await post(to.dataset.dragAndDropUrl.replaceAll("__id__", id), { body: new FormData(), headers: { Accept: "text/vnd.turbo-stream.html" } })
    from.querySelector("[data-drag-and-drop-refresh]")?.reload()

    // The target column is redrawn from the server; wait for the card's new node, then pick it
    // up again so the next H or L keeps moving it.
    for (let i = 0; i < 20; i++) {
      await new Promise(resolve => setTimeout(resolve, 50))
      const moved = board.querySelector(`.card[data-id="${id}"]`)
      if (moved && moved !== card && moved.isConnected) {
        moved.dispatchEvent(new Event("mouseenter"))
        moved.focus()
        return
      }
    }
    const moved = board.querySelector(`.card[data-id="${id}"]`)
    moved?.dispatchEvent(new Event("mouseenter"))
    moved?.focus()
  }
}

// "j", "G", "?", "esc", "enter", "ctrl+enter", "meta+k": letters keep their case, so a
// shifted letter is its own key.
function describe(event) {
  let key = event.key
  if (key === "Escape") key = "esc"
  else if (key === " ") key = "space"
  else if (key.length > 1) key = key.toLowerCase()

  const modifiers = []
  if (event.ctrlKey) modifiers.push("ctrl")
  if (event.metaKey) modifiers.push("meta")
  if (event.altKey) modifiers.push("alt")
  return [ ...modifiers, key ].join("+")
}

// data-keys="s, mod+k": alternatives separated by commas; mod is ⌘ on a Mac, Ctrl elsewhere.
function declares(element, key) {
  return element.dataset.keys.split(",").map(name => name.trim().replace("mod", MOD)).includes(key)
}

function usable(element) {
  return !element.closest("[hidden], dialog:not([open])") && element.checkVisibility()
}

function adjustCount(column, delta) {
  const counter = column.querySelector("[data-drag-and-drop-counter]")
  if (counter && /^\d+$/.test(counter.textContent)) counter.textContent = Number(counter.textContent) + delta
}

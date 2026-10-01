/*
 * Lumin consent runtime.
 *
 * Served as the tail of /consent.js after `window.__LUMIN_CONSENT__`, which
 * carries the site's banner config and its active scripts. This file is
 * plain, dependency-free JavaScript: it runs on the customer's site, not in
 * this app, so nothing here may assume a bundler, a framework, or our CSS.
 *
 * What it does, in order:
 *   1. Publishes a Google Consent Mode v2 default (denied, or granted for an
 *      opt-out site) before any tag can run.
 *   2. Loads every "necessary" script.
 *   3. Reads the visitor's stored choice. If it exists and matches the
 *      current version, loads the granted categories and stops.
 *   4. Otherwise shows the banner (and, for opt-out sites, loads everything
 *      in the meantime).
 *
 * Also honours `<script type="text/plain" data-consent="analytics">` tags
 * already in the page, `[data-consent-open]` links that reopen the panel,
 * and exposes `window.luminConsent` for the site's own code.
 */
(function () {
  "use strict";

  var boot = window.__LUMIN_CONSENT__;
  if (!boot || !boot.config || window.__luminConsentBooted) return;
  window.__luminConsentBooted = true;

  var config = boot.config;
  var scripts = boot.scripts || [];
  var OPTIONAL = ["functional", "analytics", "marketing"];
  var COOKIE = "lumin_consent";
  var offered = OPTIONAL.filter(function (c) {
    return config.categories && config.categories[c] && config.categories[c].enabled;
  });
  var optOut = config.mode === "opt_out";

  var state = { decided: false, choices: choiceSet(false) };
  var injected = {};
  var listeners = [];
  var ui = { root: null, banner: null, prefs: null };

  // ---- helpers ------------------------------------------------------------

  function choiceSet(value) {
    var out = {};
    OPTIONAL.forEach(function (c) { out[c] = offered.indexOf(c) !== -1 && !!value; });
    return out;
  }

  function copyChoices() {
    var out = {};
    OPTIONAL.forEach(function (c) { out[c] = !!state.choices[c]; });
    return out;
  }

  function whenReady(fn) {
    if (document.body) fn();
    else document.addEventListener("DOMContentLoaded", fn);
  }

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "text") node.textContent = attrs[k];
      else if (k === "html") node.innerHTML = attrs[k];
      else if (k.indexOf("on") === 0) node.addEventListener(k.slice(2), attrs[k]);
      else node.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { if (c) node.appendChild(c); });
    return node;
  }

  // ---- storage --------------------------------------------------------------

  function readStored() {
    var raw = null;
    try {
      var match = document.cookie.match(new RegExp("(?:^|; )" + COOKIE + "=([^;]*)"));
      if (match) raw = decodeURIComponent(match[1]);
      if (!raw && window.localStorage) raw = window.localStorage.getItem(COOKIE);
    } catch (e) { /* blocked storage: treat as no choice */ }
    if (!raw) return null;
    try {
      var data = JSON.parse(raw);
      if (!data || data.v !== config.version || !data.c) return null;
      var ageDays = (Date.now() - (data.at || 0)) / 86400000;
      if (ageDays > (config.expiry_days || 365)) return null;
      return data;
    } catch (e) {
      return null;
    }
  }

  function store(choices) {
    var value = JSON.stringify({ v: config.version, at: Date.now(), c: choices });
    var maxAge = (config.expiry_days || 365) * 86400;
    var secure = location.protocol === "https:" ? "; Secure" : "";
    try {
      document.cookie = COOKIE + "=" + encodeURIComponent(value) + "; Max-Age=" + maxAge + "; Path=/; SameSite=Lax" + secure;
      if (window.localStorage) window.localStorage.setItem(COOKIE, value);
    } catch (e) { /* storage blocked: the choice lasts for this page */ }
  }

  // ---- Google Consent Mode v2 -------------------------------------------------

  function gtagStub() {
    window.dataLayer = window.dataLayer || [];
    if (typeof window.gtag !== "function") {
      window.gtag = function () { window.dataLayer.push(arguments); };
    }
  }

  function consentSignal(kind, choices) {
    if (!config.google_consent_mode) return;
    gtagStub();
    var g = function (on) { return on ? "granted" : "denied"; };
    var params = {
      ad_storage:              g(choices.marketing),
      ad_user_data:            g(choices.marketing),
      ad_personalization:      g(choices.marketing),
      analytics_storage:       g(choices.analytics),
      functionality_storage:   g(choices.functional),
      personalization_storage: g(choices.functional),
      security_storage:        "granted"
    };
    if (kind === "default") params.wait_for_update = 500;
    window.gtag("consent", kind, params);
  }

  // ---- loading scripts -------------------------------------------------------

  function mount(node, placement) {
    if (placement === "body_start") document.body.insertBefore(node, document.body.firstChild);
    else if (placement === "body_end") document.body.appendChild(node);
    else document.head.appendChild(node);
  }

  function inject(script) {
    if (injected[script.id]) return;
    injected[script.id] = script.category;
    var run = function () {
      if (script.src) {
        var ext = document.createElement("script");
        ext.src = script.src;
        ext.async = !!script.async;
        ext.defer = !!script.defer;
        ext.setAttribute("data-lumin-script", script.id);
        mount(ext, script.placement);
      }
      if (script.code) {
        var inline = document.createElement("script");
        inline.text = script.code;
        inline.setAttribute("data-lumin-script", script.id);
        mount(inline, script.placement);
      }
    };
    if (script.placement === "head") run();
    else whenReady(run);
  }

  // Tags the site put in its own markup as `type="text/plain"
  // data-consent="<category>"` — the usual way to hold a snippet back
  // until a CMP says go.
  function activateInlineTags(choices) {
    whenReady(function () {
      var nodes = document.querySelectorAll('script[type="text/plain"][data-consent]');
      Array.prototype.forEach.call(nodes, function (node) {
        var category = node.getAttribute("data-consent");
        if (category !== "necessary" && !choices[category]) return;
        var live = document.createElement("script");
        Array.prototype.forEach.call(node.attributes, function (a) {
          if (a.name !== "type" && a.name !== "data-consent") live.setAttribute(a.name, a.value);
        });
        live.text = node.text;
        node.parentNode.replaceChild(live, node);
      });
    });
  }

  function applyChoices(choices) {
    scripts.forEach(function (s) {
      if (s.category === "necessary" || choices[s.category]) inject(s);
    });
    activateInlineTags(choices);
  }

  function loadedSomethingIn(category) {
    return Object.keys(injected).some(function (id) { return injected[id] === category; });
  }

  // ---- deciding --------------------------------------------------------------

  function emit() {
    var detail = { choices: copyChoices(), decided: state.decided, version: config.version };
    listeners.forEach(function (fn) { try { fn(detail); } catch (e) { /* a listener's error is its own */ } });
    try {
      document.dispatchEvent(new CustomEvent("lumin:consent", { detail: detail }));
    } catch (e) { /* very old browser */ }
  }

  function decide(next) {
    var previous = state.choices;
    var choices = choiceSet(false);
    offered.forEach(function (c) { choices[c] = !!next[c]; });

    state.choices = choices;
    state.decided = true;
    store(choices);
    consentSignal("update", choices);

    // A script that already ran can't be un-run. Withdrawing a category
    // that had loaded something is honoured by starting the page over.
    var withdrew = OPTIONAL.some(function (c) { return previous[c] && !choices[c] && loadedSomethingIn(c); });

    applyChoices(choices);
    emit();
    hide(ui.banner);
    hide(ui.prefs);
    if (withdrew) window.location.reload();
  }

  // ---- UI ----------------------------------------------------------------------

  var CSS =
    "#lumin-consent{--lc-bg:#fff;--lc-fg:#111827;--lc-muted:#6b7280;--lc-border:#e5e7eb;--lc-accent:#111827;--lc-accent-fg:#fff;--lc-radius:12px;position:fixed;z-index:2147483000;font:inherit;line-height:1.45;color:var(--lc-fg)}" +
    "#lumin-consent.lc-dark{--lc-bg:#111827;--lc-fg:#f9fafb;--lc-muted:#9ca3af;--lc-border:#374151;--lc-accent:#f9fafb;--lc-accent-fg:#111827}" +
    "@media (prefers-color-scheme:dark){#lumin-consent.lc-auto{--lc-bg:#111827;--lc-fg:#f9fafb;--lc-muted:#9ca3af;--lc-border:#374151;--lc-accent:#f9fafb;--lc-accent-fg:#111827}}" +
    "#lumin-consent *{box-sizing:border-box}" +
    "#lumin-consent .lc-card{background:var(--lc-bg);border:1px solid var(--lc-border);border-radius:var(--lc-radius);box-shadow:0 12px 40px rgba(0,0,0,.18);padding:20px;max-width:100%}" +
    "#lumin-consent.lc-bottom{left:16px;right:16px;bottom:16px}#lumin-consent.lc-bottom .lc-card{max-width:960px;margin:0 auto}" +
    "#lumin-consent.lc-bottom-left{left:16px;bottom:16px;max-width:420px}#lumin-consent.lc-bottom-right{right:16px;bottom:16px;max-width:420px}" +
    "#lumin-consent.lc-center{inset:0;display:flex;align-items:center;justify-content:center;padding:16px;background:rgba(0,0,0,.35)}#lumin-consent.lc-center .lc-card{max-width:520px;width:100%}" +
    "#lumin-consent h2{margin:0 0 6px;font-size:16px;font-weight:600}#lumin-consent p{margin:0;font-size:14px;color:var(--lc-muted)}" +
    "#lumin-consent a{color:inherit;text-decoration:underline}" +
    "#lumin-consent .lc-actions{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}" +
    "#lumin-consent button{font:inherit;font-size:14px;font-weight:500;border-radius:calc(var(--lc-radius) - 4px);padding:9px 14px;cursor:pointer;border:1px solid var(--lc-border);background:transparent;color:var(--lc-fg)}" +
    "#lumin-consent button.lc-primary{background:var(--lc-accent);color:var(--lc-accent-fg);border-color:var(--lc-accent)}" +
    "#lumin-consent button:focus-visible{outline:2px solid var(--lc-accent);outline-offset:2px}" +
    "#lumin-consent .lc-prefs-wrap{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;padding:16px;background:rgba(0,0,0,.35)}" +
    "#lumin-consent .lc-prefs{max-width:520px;width:100%;max-height:90vh;overflow:auto}" +
    "#lumin-consent .lc-row{display:flex;gap:12px;align-items:flex-start;padding:12px 0;border-top:1px solid var(--lc-border)}#lumin-consent .lc-row:first-of-type{border-top:0}" +
    "#lumin-consent .lc-row label{font-size:14px;font-weight:600;display:block}#lumin-consent .lc-row p{font-size:13px;margin-top:2px}" +
    "#lumin-consent .lc-row input{margin-top:4px;width:16px;height:16px;flex:none;accent-color:var(--lc-accent)}" +
    "#lumin-consent .lc-close{position:absolute;top:10px;right:10px;border:0;padding:6px 8px;font-size:18px;line-height:1}" +
    "#lumin-consent .lc-hidden{display:none}" +
    "@media (max-width:640px){#lumin-consent.lc-bottom-left,#lumin-consent.lc-bottom-right{left:16px;right:16px;max-width:none}#lumin-consent .lc-actions button{flex:1 1 auto}}";

  function show(node) { if (node) node.classList.remove("lc-hidden"); }
  function hide(node) { if (node) node.classList.add("lc-hidden"); }

  function ensureRoot() {
    if (ui.root) return;
    ui.root = el("div", { id: "lumin-consent", class: "lc-" + (config.position || "bottom") + " lc-" + (config.theme || "auto") });
    ui.root.appendChild(el("style", { text: CSS }));
    document.body.appendChild(ui.root);
  }

  function buildBanner() {
    var b = config.banner;
    var policy = b.policy_url ? el("a", { href: b.policy_url, target: "_blank", rel: "noopener", text: b.policy_label || "Privacy policy" }) : null;
    var message = el("p", { id: "lumin-consent-message", text: b.message + (policy ? " " : "") }, [policy]);
    var actions = el("div", { class: "lc-actions" }, [
      el("button", { type: "button", class: "lc-primary", text: b.accept_label, onclick: function () { decide(choiceSet(true)); } }),
      config.show_reject ? el("button", { type: "button", text: b.reject_label, onclick: function () { decide(choiceSet(false)); } }) : null,
      offered.length ? el("button", { type: "button", text: b.customize_label, onclick: openPrefs }) : null
    ]);
    ui.banner = el("div", { class: "lc-card", role: "dialog", "aria-modal": config.position === "center" ? "true" : "false", "aria-labelledby": "lumin-consent-title", "aria-describedby": "lumin-consent-message" }, [
      el("h2", { id: "lumin-consent-title", text: b.title }),
      message,
      actions
    ]);
    ui.root.appendChild(ui.banner);
  }

  function buildPrefs() {
    var b = config.banner;
    var inputs = {};
    var rows = [
      el("div", { class: "lc-row" }, [
        el("input", { type: "checkbox", checked: "checked", disabled: "disabled", "aria-label": config.necessary.label }),
        el("div", {}, [el("label", { text: config.necessary.label }), el("p", { text: config.necessary.description })])
      ])
    ];
    offered.forEach(function (c) {
      var cat = config.categories[c];
      var input = el("input", { type: "checkbox", id: "lumin-consent-" + c });
      inputs[c] = input;
      rows.push(el("div", { class: "lc-row" }, [
        input,
        el("div", {}, [el("label", { for: "lumin-consent-" + c, text: cat.label }), el("p", { text: cat.description })])
      ]));
    });
    var card = el("div", { class: "lc-card lc-prefs", role: "dialog", "aria-modal": "true", "aria-labelledby": "lumin-consent-prefs-title", style: "position:relative" }, [
      el("button", { type: "button", class: "lc-close", "aria-label": "Close", text: "×", onclick: closePrefs }),
      el("h2", { id: "lumin-consent-prefs-title", text: b.customize_label }),
      el("p", { text: b.message }),
      el("div", { style: "margin-top:12px" }, rows),
      el("div", { class: "lc-actions" }, [
        el("button", { type: "button", class: "lc-primary", text: b.save_label, onclick: function () {
          var next = {};
          offered.forEach(function (c) { next[c] = inputs[c].checked; });
          decide(next);
        } }),
        el("button", { type: "button", text: b.accept_label, onclick: function () { decide(choiceSet(true)); } })
      ])
    ]);
    ui.prefs = el("div", { class: "lc-prefs-wrap lc-hidden", onkeydown: function (e) { if (e.key === "Escape") closePrefs(); } }, [card]);
    ui.prefsInputs = inputs;
    ui.root.appendChild(ui.prefs);
  }

  function openPrefs() {
    whenReady(function () {
      ensureRoot();
      if (!ui.prefs) buildPrefs();
      offered.forEach(function (c) { ui.prefsInputs[c].checked = state.decided ? !!state.choices[c] : optOut; });
      // One dialog at a time: the banner comes back if the panel is closed
      // without a decision (see closePrefs).
      hide(ui.banner);
      show(ui.prefs);
      var first = ui.prefs.querySelector("input:not([disabled])") || ui.prefs.querySelector("button");
      if (first) first.focus();
    });
  }

  function closePrefs() {
    hide(ui.prefs);
    if (!state.decided) show(ui.banner);
  }

  function showBanner() {
    whenReady(function () {
      ensureRoot();
      if (!ui.banner) buildBanner();
      show(ui.banner);
    });
  }

  document.addEventListener("click", function (e) {
    var trigger = e.target && e.target.closest ? e.target.closest("[data-consent-open]") : null;
    if (!trigger) return;
    e.preventDefault();
    openPrefs();
  });

  // ---- public API --------------------------------------------------------------

  window.luminConsent = {
    version: config.version,
    categories: offered.slice(),
    get: function () { return { decided: state.decided, choices: copyChoices() }; },
    acceptAll: function () { decide(choiceSet(true)); },
    rejectAll: function () { decide(choiceSet(false)); },
    update: function (partial) { var next = copyChoices(); Object.keys(partial || {}).forEach(function (k) { next[k] = !!partial[k]; }); decide(next); },
    open: openPrefs,
    on: function (fn) { if (typeof fn === "function") listeners.push(fn); },
    off: function (fn) { listeners = listeners.filter(function (l) { return l !== fn; }); }
  };

  // ---- boot ----------------------------------------------------------------------

  consentSignal("default", optOut ? choiceSet(true) : choiceSet(false));

  var stored = readStored();
  if (stored) {
    state.decided = true;
    state.choices = choiceSet(false);
    offered.forEach(function (c) { state.choices[c] = !!stored.c[c]; });
    consentSignal("update", state.choices);
    applyChoices(state.choices);
    emit();
  } else {
    // Opt-out: everything runs until the visitor says otherwise. Opt-in:
    // only what needs no permission.
    state.choices = optOut ? choiceSet(true) : choiceSet(false);
    applyChoices(state.choices);
    emit();
    showBanner();
  }
})();

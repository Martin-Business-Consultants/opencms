# Scripts & consent

Two things that only make sense together: the third-party tags the public
site loads (**Tools → Scripts**), and the banner that asks the visitor before
they run (**Settings → Consent**). A script is filed under a consent
category; the banner asks about categories; the embed loads a script only
once its category has been granted.

## Scripts

`Script` rows: a label, a vendor, a **category**, a placement, and an
external `src` and/or inline `code` (both is the loader-plus-config
pattern, e.g. gtag). `active` pauses a script without deleting it.

| Category | Loads | Meaning |
|---|---|---|
| `necessary` | always, before the banner | needed for the site to work |
| `functional` | on consent | remembers choices; chat, embedded video |
| `analytics` | on consent | aggregate measurement |
| `marketing` | on consent | advertising profiles and pixels |

**Presets** (`Scripts::Presets`) carry the vendor's own install snippet with
`{{id}}` where the account ID goes: GA4, Google Tag Manager, Google Ads,
Meta Pixel, Microsoft Clarity, Hotjar, LinkedIn Insight, TikTok Pixel,
Plausible, Fathom. Adding a vendor is one more entry in `ALL`. IDs are
validated against `ID_FORMAT` so a paste can't break out of the snippet.

## Consent settings

`Consent::Config` reads and normalizes `Setting["consent"]`. Everything has
a default, so a site that never opened the page still gets a coherent
banner the moment `enabled` flips on.

- **mode** — `opt_in` (nothing but necessary loads until the visitor agrees;
  EU/UK) or `opt_out` (everything loads; the banner offers a way out; parts
  of the US only).
- **categories** — which of functional/analytics/marketing are offered, with
  their label and description. A category switched off is not offered and
  its scripts never load.
- **banner** — title, message, button labels, privacy-policy link.
- **position / theme** — bottom bar, corner card or centered dialog; light,
  dark or the visitor's system.
- **google_consent_mode** — emit Consent Mode v2 `default` and `update`
  calls so Google tags model what wasn't granted.
- **version / expiry_days** — a stored choice carries the version it was
  made under; *Ask everyone again* bumps it.

Nothing here enables tracking on its own: the banner ships off, and until it
is on the embed serves a comment and no scripts.

## Delivery

| URL | Auth | What |
|---|---|---|
| `GET /consent.js` | none, CORS `*` | the embed: `window.__LUMIN_CONSENT__ = {config, scripts}` + the runtime |
| `GET /consent.json` | none, CORS `*` | the same payload as JSON |
| `GET /api/consent` | token | the payload, for a build |
| `GET /api/scripts` | token + `scripts:read` | every script, inactive included |

The CMS doesn't render pages itself, so the embed only ever runs on the
published site.

### Installing on the Astro site

```html
<script src="https://<cms-host>/consent.js" defer></script>
```

Put it in `<head>` before any other tag. That is the whole integration: the
runtime (`lib/consent/cmp.js`, plain dependency-free JS) draws the banner,
stores the choice in a `lumin_consent` cookie (mirrored to localStorage),
and injects granted scripts where their placement says.

It also honours:

- `<script type="text/plain" data-consent="analytics">…</script>` in the
  site's own markup — activated when the category is granted.
- `<a href="#" data-consent-open>Cookie settings</a>` — reopens the choices.
- `document.addEventListener("lumin:consent", e => e.detail.choices)` and
  `window.luminConsent` (`get()`, `acceptAll()`, `rejectAll()`,
  `update({analytics: true})`, `open()`, `on(fn)`).

A build that wants its own banner reads `/api/consent` instead and does the
gating itself; the payload is the same.

Withdrawing a category that had already loaded a script reloads the page —
a script that has run cannot be un-run, and pretending otherwise would be
a lie to the visitor.

## Is it on the site?

The site audit (`Reports::Definitions::SiteAudit`, see `docs/reporting.md`)
answers this per script: the probe reads `window.__LUMIN_CONSENT__.scripts`
from the embed the site loaded and calls `luminConsent.acceptAll()` in
DataForSEO's sandboxed browser, then records the `data-lumin-script` ids the
runtime injected. Tools → Scripts shows the verdict per row.

## Who sees this

`scripts:read` / `consent:read` are granted widely (Editor, the site's
token). `scripts:write`, `scripts:delete` and `consent:write` are the
administrator's: a script is JavaScript in every visitor's browser. The
backfill migration follows `webhooks:write` for existing roles.

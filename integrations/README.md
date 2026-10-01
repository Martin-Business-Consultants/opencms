# Integrations

Reference integrations for consuming this CMS from a public-facing site.
Copy an integration into your project and adapt — these aren't published as
npm/gem packages, they're starter snippets that match the shape of this
specific CMS API and webhook payloads.

## What's here

- **`astro/`** — TypeScript client + webhook handler for an Astro site.
  Mirrors the shape of `/api/pages`, `/api/collections`, `/api/globals`,
  `/api/assets`, `/api/sitemap`, and verifies the HMAC-SHA256 signature
  on outbound webhooks (`X-CMS-Signature`). `.github/workflows/cms-publish.yml`
  rebuilds and deploys the site when the CMS's GitHub deploy provider sends
  its `cms-publish` event.

## Conventions across integrations

- **Auth** is always a Bearer API token minted under
  Settings → API tokens. Tokens carry scopes; mint one with the minimum
  scopes the consumer needs (typically `pages:read`, `entries:read`,
  `collections:read`, `globals:read`, `assets:read`).
- **Webhook signatures** are HMAC-SHA256 over the raw request body, hex-
  encoded, prefixed with `sha256=`, in header `X-CMS-Signature`. Compare
  with constant time.
- **One install per site.** Point the integration's `CMS_BASE_URL` at the
  install's origin (`https://acme.cms.example.com`) — there's no site header.

Not to be confused with CMS plugins (`engines/`, `plugins/`, docs/plugins.md),
which extend the CMS itself.

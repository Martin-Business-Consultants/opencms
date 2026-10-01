<!-- librepublish:cms-frontend -->
# This site is the frontend of a headless CMS

The content of this site — its pages, collections, navigation, footer, forms,
redirects, scripts — lives in the __SITE__ CMS at __CMS_URL__. The CMS never
renders HTML for visitors. It stores content and serves it as JSON; **this
repo fetches that JSON at build time and renders it**. Keep that split:

- **Content changes happen in the CMS**, not here. Don't hardcode copy, nav
  items, prices, hours or anything else an editor would expect to change. If
  a template needs text, it reads it from a global or a field.
- **Structure and presentation happen here**: layouts, components, styling,
  routing, build config.

This file is written by the CMS integration (`cms()` in `astro.config`) on
every `astro dev` and `astro build`, between the `librepublish:cms-frontend`
markers. Edit outside them; inside, your changes are replaced.

## Where things are

| | |
|---|---|
| `src/lib/cms/cms.ts` | The typed client. `cms.pages`, `cms.collections`, `cms.globals`, `cms.forms`, `cms.assets`, `cms.sitemap`, `cms.manifest`. |
| `src/lib/cms/types.ts` | The JSON shapes, as TypeScript. |
| `src/lib/cms/blocks.ts` | `resolveBlocks(blocks, components)`: block type → component. |
| `src/lib/cms/emails.ts` | Form email templates (see below). |
| `.cms/manifest.json` | **The content model, fetched from the CMS**: every collection's fields, every block type's fields and JSON schema, every global, the forms. Read it before writing a component for CMS data — don't guess a field name. Refreshed on every dev start and build. |

Env: `CMS_BASE_URL` (the CMS's origin) and `CMS_API_TOKEN` (a read-only
*service token* from Settings › Service tokens, plus `forms:templates` if the
site builds form emails). Never commit either.

## The JSON

Every read is `GET __CMS_URL__/api/…` with `Authorization: Bearer <token>`,
JSON back. Add `?resolve=assets` to have asset ids expanded into URLs in an
`assets` map beside the record.

**A page** — `GET /api/pages/<path>` → `{ page, assets? }`

```json
{
  "id": 3, "slug": "team", "path": "about/team", "parent_id": 2, "depth": 1,
  "title": "Our team", "status": "published", "locale": "en",
  "blocks": [ { "id": "…", "type": "hero", "version": 1, "data": { "heading": "…" } } ],
  "frontmatter": { "…": "the page's own fields" },
  "seo": { "meta_title": "…", "meta_description": "…", "canonical_url": "…", "noindex": false },
  "published_at": "…", "created_at": "…", "updated_at": "…"
}
```

A page is served at `/<path>`; `home` is `/`. List them with
`GET /api/pages?status=published`.

**An entry** — `GET /api/collections/<collection>/entries/<slug>` → `{ entry, assets? }`

```json
{
  "id": 9, "slug": "spring-menu", "title": "Spring menu", "status": "published",
  "collection_slug": "posts", "locale": "en",
  "frontmatter": { "…": "the collection's fields" },
  "body_markdown": "<p>…</p>",
  "blocks": [], "seo": {}, "published_at": "…"
}
```

An entry is served at `/<collection>/<slug>` unless its SEO canonical says
otherwise. List with `GET /api/collections/<collection>/entries?status=published`.
`body_markdown` holds **HTML** for anything saved from the admin's rich-text
editor, and Markdown for older entries; render it as HTML (a Markdown
renderer passes HTML through).

**A global** — `GET /api/globals/<slug>` → `{ global, assets? }`: one-of-a-kind
content (navigation, footer, contact details) as `data`, shaped by its `fields`.

**Blocks** are `{ id, type, version, data }`. `type` is a block type's slug;
its fields are in `.cms/manifest.json` under `block_types`. Map each type to a
component with `resolveBlocks` and skip types you don't know yet (it does) —
editors can add a block type before the site has a component for it.

**Field values:** `text` fields are HTML (render with `set:html`),
`markdown` fields are Markdown, `asset` fields are an asset id (look it up in
`assets` with `?resolve=assets`), `link` fields are
`{ kind: "url" | "page" | "entry" | "asset", value }`, `record_ref` is an
entry slug.

Also: `GET /api/sitemap` (what to put in sitemap.xml), `GET /api/redirects`
(the active redirect rules, for the host's redirect config),
`GET /api/manifest` (the content model, as in `.cms/manifest.json`).

## What the site does for the CMS

- **Rebuilds.** Publishing in the CMS triggers a rebuild (a GitHub
  `repository_dispatch` of type `cms-publish`, or a deploy hook). Builds are
  static: fetch in `getStaticPaths` and page frontmatter, not in the browser.
- **Drafts.** Editors preview unsaved pages at
  `/_preview/<path>?preview=<token>`: read the draft from
  `GET /api/preview_drafts/<token>` (no bearer token; the token is the key)
  and render it like a page. That route must not be prerendered.
- **Forms.** A form's fields come from `cms.forms.get(slug)`; the site renders
  them and posts to `POST __CMS_URL__/api/forms/<slug>/submissions` (public,
  CORS-allowed for the site's origin). Include an empty hidden field named
  `_hp` — bots fill it, and those submissions are dropped. Show the form's
  `success_message` on success.
- **Form emails.** The CMS sends each form's notification and confirmation
  emails; the site gives them its design. `src/pages/emails/[form]/[kind].astro`
  renders each email's blocks with email-safe markup (tables, inline styles),
  leaving `{{tokens}}` in; the integration sends the built templates to the
  CMS and removes them from the deployed site.
- **Scripts and consent.** Load third-party scripts only through the CMS:
  `<script src="__CMS_URL__/consent.js" defer></script>` in the layout's head
  shows the consent banner and loads each script once its category is
  granted. Don't paste analytics tags into templates.

## Changing the CMS itself

Content, fields, collections, block types and settings are changed in the CMS
(its admin, or the `cms` CLI: `curl -fsSL __CMS_URL__/agent/install.sh | sh`),
not from this repo. The one thing this repo writes to the CMS is what its
build produced: email templates and a build report.
<!-- /librepublish:cms-frontend -->

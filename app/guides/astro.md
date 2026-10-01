---
title: "Working with an Astro site"
summary: "Connect a site in one line, then fetch pages, entries and globals and render their blocks."
position: 2
---

The site is an Astro app in its own repo. It reads this CMS at build time
and renders what it gets; nothing about the site's look lives here.

## Connect it

In the site's project (its root or its `src/`):

```sh
curl -fsSL {{cms_url}}/frontend/install.sh | sh
```

It downloads the integration into `src/lib/cms/`, adds `cms()` to
`astro.config`, adds a route for the form emails' design, and gets the site
a **read-only service token of its own** — you approve it in your browser,
signed in here — which it writes to `.env` with the CMS's address.

Set the same two variables where the site builds (your host, or the repo's
secrets):

```sh
CMS_BASE_URL={{cms_url}}
CMS_API_TOKEN=…   # the site's service token
```

From then on, every `astro dev` and `astro build` writes **`AGENTS.md`** into
the site's repo (how the site works with this CMS, for an AI working there)
and saves the content model to **`.cms/manifest.json`**. Commit both. After a
build it sends the form email templates and reports the build — Developers
shows the last one.

## Fetch content

```ts
import { cms } from "../lib/cms/cms";

const page = await cms.pages.get("about/team");          // a page by its path
const posts = await cms.collections.entries("posts", { status: "published" });
const nav = await cms.globals.get("nav");
```

Fetch in `getStaticPaths` and page frontmatter — the build is static. List
every published page to generate routes:

```ts
export async function getStaticPaths() {
  const { pages } = await cms.pages.list({ status: "published" });
  return pages.map((p) => ({ params: { slug: p.path === "home" ? undefined : p.path } }));
}
```

## Render blocks

A page's `blocks` are `{ id, type, version, data }`. Map each type to a
component; types the site doesn't know yet are skipped, so editors can add a
block type before it has one.

```astro
---
import { resolveBlocks } from "../lib/cms/blocks";
import Hero from "../components/blocks/Hero.astro";
import Prose from "../components/blocks/Prose.astro";
const blocks = resolveBlocks(page.blocks, { hero: Hero, prose: Prose });
---
{blocks.map(({ Component, data }) => <Component {...data} />)}
```

Each block type's fields are in `.cms/manifest.json` under `block_types`.

## Field values

- **Rich text** (`text`) is HTML: render it with `set:html`. So is an entry's
  `body_markdown` when it was written in the rich-text editor.
- **Markdown** fields are Markdown.
- **Assets** are ids: ask for `?resolve=assets` and look them up in the
  `assets` beside the record (URL, alt text, caption, responsive sources).
- **Links** are `{ kind: "url" | "page" | "entry" | "asset", value }`.

## The rest of the site's side

- **SEO** — each record's `seo` (meta title and description, canonical,
  social image, noindex). Build `sitemap.xml` from `cms.sitemap()`.
- **Redirects** — `GET /api/redirects` for the host's redirect rules.
- **Previews** — editors preview drafts at `/_preview/<path>?preview=<token>`;
  read the draft from `GET /api/preview_drafts/<token>`. Don't prerender that
  route.
- **Forms** — render a form's fields from `cms.forms.get(slug)` and post to
  `{{cms_url}}/api/forms/<slug>/submissions`, with an empty hidden `_hp`
  field (bots fill it in).
- **Form emails** — `src/pages/emails/[form]/[kind].astro` gives each form's
  emails the site's design; the CMS sends them. Until a build sends a
  template for an email's current blocks, it goes out in the CMS's own layout.
- **Scripts** — load analytics and pixels only through
  `<script src="{{cms_url}}/consent.js" defer></script>`, which asks for
  consent first.

## Rebuilds

Publishing here triggers a rebuild (Settings › Deploy): a GitHub
`repository_dispatch` the repo's `cms-publish` workflow answers, or a host's
build hook.

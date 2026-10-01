# Astro integration

The CMS is headless: it keeps the content and serves it as JSON, and an
Astro site renders it. This folder is what a site needs to work with it: a
typed client (`cms.ts`, `types.ts`), block helpers (`blocks.ts`), the
sitemap, form emails (`emails.ts`), a webhook receiver, and **the
integration** (`integration.ts`) that ties them together.

## Install

Run this in the Astro project (its root or its `src/`):

```sh
curl -fsSL https://<your-cms>/frontend/install.sh | sh
```

It downloads these files into `src/lib/cms/` (and the form email route into
`src/pages/emails/`, unless there's one), adds `cms()` to `astro.config`,
and gets the site a read-only service token of its own — you approve it in
your browser, signed in to the CMS — which it writes to `.env` with the
CMS's address. Re-run it to refresh the files. In CI, pass a token:
`CMS_API_TOKEN=mbc_… sh -c "$(curl -fsSL …/frontend/install.sh)"`.

### By hand

This isn't an npm package; copy the files into your Astro project:

```sh
mkdir -p src/lib/cms
cp <cms-repo>/integrations/astro/*.ts src/lib/cms/
cp <cms-repo>/integrations/astro/.env.example .env.example
```

Add the integration to `astro.config.mjs`:

```js
import { defineConfig } from "astro/config";
import { cms } from "./src/lib/cms/integration";

export default defineConfig({ integrations: [cms()] });
```

Then drop these env vars into `.env` (and your hosting provider):

```
CMS_BASE_URL=https://acme.cms.example.com
CMS_API_TOKEN=mbc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
CMS_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxxxxxxxxxxxxx
```

`CMS_API_TOKEN` is a read-only **service token** (Settings › Service
tokens), with `forms:templates` added if the site designs form emails.
Mint a webhook with the events you care about (`page.published`,
`entry.published`, `global.updated`, plus the `*.deleted` events) and copy
its signing secret into `CMS_WEBHOOK_SECRET`.

## What the integration does

On every `astro dev` and `astro build`:

- **AGENTS.md.** It writes the CMS's frontend guide (`/frontend/AGENTS.md`
  on the CMS) into the project's `AGENTS.md`, between
  `<!-- librepublish:cms-frontend -->` markers — the rest of the file is
  yours — and adds a `CLAUDE.md` that imports it when there isn't one. An AI
  working in the repo then knows the content comes from the CMS, what the
  JSON looks like, and what not to hardcode.
- **`.cms/manifest.json`.** It saves the content model: every collection's
  fields, every block type's fields and JSON schema, every global and form.
  Components get written against real names instead of guesses.

Commit both, so an agent without CMS credentials still has them.

After `astro build`, it sends the form email templates the build made (see
*Form emails*) and reports the build to the CMS, whose Developers screen
and dashboard then show when the site last built and what with.

Without the two variables, `astro dev` warns and carries on; `astro build`
stops. Each part can be turned off: `cms({ agentsMd: false, manifest: false,
emails: false, report: false })`.

## Reading content

```ts
import { cms } from "~/lib/cms/cms";

const page = await cms.pages.get("home");
const posts = await cms.collections.entries("blog", { status: "published" });
const general = await cms.globals.get("general");
const sitemap = await cms.sitemap();
```

Every method throws on non-2xx, returns plain JSON typed against the
declarations in `types.ts`. No global cache — wrap calls with Astro's
own `getStaticPaths` / `Astro.url` caching idioms as needed.

## Receiving webhooks

Drop `webhook-handler.ts` into `src/pages/api/cms/webhook.ts` and Astro
serves it as a POST endpoint. The handler verifies the HMAC-SHA256
signature, parses the JSON body, and dispatches by event name —
typically you'd call your `purgeCache` / `revalidate` / on-demand
rebuild from `event.data` (which contains `slug`, `path`, `status`,
etc. depending on the event).

```ts
// src/pages/api/cms/webhook.ts
import type { APIRoute } from "astro";
import { handleWebhook } from "~/lib/cms/webhook-handler";

export const POST: APIRoute = ({ request }) =>
  handleWebhook(request, {
    "page.published":   ({ data }) => purgeCache(`/${data.path}`),
    "page.unpublished": ({ data }) => purgeCache(`/${data.path}`),
    "page.deleted":     ({ data }) => purgeCache(`/${data.path}`),
    "entry.published":  ({ data }) => purgeCache(`/${data.collection_slug}/${data.slug}`),
    "global.updated":   () => purgeAllCache(),
  });
```

If you're on Netlify or similar, point the platform's "build hook" at
this route via a fetch from a small wrapper that reads the env var —
or just trigger a rebuild directly from the handler instead of cache
purging.

## Rebuilding when the CMS publishes

With the CMS's GitHub deploy provider (Settings › Deploy, repo and token in
Settings › GitHub), every publish sends a `repository_dispatch` of type
`cms-publish` to the site repo. `.github/workflows/cms-publish.yml` listens
for it (and for pushes to `main`), builds the site against the CMS and
deploys it:

```sh
mkdir -p .github/workflows
cp <cms-repo>/integrations/astro/.github/workflows/cms-publish.yml .github/workflows/
```

Add the repository secrets `CMS_BASE_URL` and `CMS_API_TOKEN` (the site's
read-only service token), then replace the workflow's placeholder deploy step
with the one for your host (Cloudflare Pages, Netlify and GitHub Pages are
written out, commented). Several publishes in a row cancel each other's older
builds, so only the newest content deploys.

## Form emails

A form's notification and confirmation emails are content in the CMS: a
subject and blocks (heading, text, button, image, submission answers, divider,
spacer), edited like a page. The CMS sends them. The site gives them its
design: its build renders each email's blocks into a template and hands it
to the CMS, which fills in each submission's `{{tokens}}` and sends it.

1. Copy the example route and make it yours (colours, type, logo):

   ```sh
   mkdir -p "src/pages/emails/[form]"
   cp "<cms-repo>/integrations/astro/examples/emails/[form]/[kind].astro" "src/pages/emails/[form]/"
   ```

   It renders one page per form and kind (`emailTemplatePaths()`), keeps the
   `{{tokens}}` as they are, stamps the blocks' digest into `<head>`
   (`digestMeta(email)`), and marks the answers table's row for the CMS to
   repeat (`answersRow(block)`, holding `{{answer.label}}` and
   `{{answer.value}}`). Email HTML is tables and inline styles, so these are
   email components, not your site's.

2. The `cms()` integration sends the built templates to the CMS when
   `astro build` finishes and then removes them from `dist/` (pass
   `cms({ keepEmails: true })` to deploy them too).

3. Give the build's token `forms:templates` as well as its read
   capabilities (the built-in Site role has it on a new install; on an
   existing one, tick it under Settings › Roles).

The CMS sends a template only while it was built from the email's current
blocks. Saving an email schedules a rebuild; until it lands, the email goes
out in the CMS's own layout, so nothing waits on the site. The email editor's
Site template box says which one is live, and its Preview shows it.

## Signing requests back to the CMS

Outbound (CMS → site) is signed; inbound (site → CMS) uses the bearer
token. There's no separate signing for inbound — TLS + the token is
enough. Don't reuse `CMS_WEBHOOK_SECRET` for anything other than
verifying webhook payloads.

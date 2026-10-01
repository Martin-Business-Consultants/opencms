/**
 * Form emails in the site's own design. The CMS keeps what a form's
 * notification and confirmation emails say (blocks: heading, text, button,
 * image, submission answers, divider, spacer) and sends them; the site gives
 * them its look.
 *
 * How it fits together:
 *
 *   1. A page route renders each email's blocks with your email components,
 *      leaving {{tokens}} in as they are — `src/pages/emails/[form]/[kind].astro`,
 *      see examples/emails/[form]/[kind].astro. `emailTemplatePaths()` is its
 *      getStaticPaths.
 *   2. The template stamps the digest of the blocks it was built from
 *      (`digestMeta(email)`), and marks one row for the CMS to repeat per
 *      answer (`answersRow(block)`, with {{answer.label}} and {{answer.value}}).
 *   3. The `cms()` integration (integration.ts) sends every built template
 *      to the CMS at the end of the build, and by default takes them out of
 *      the deployed site. (`cmsEmailTemplates()` does only that, on its own.)
 *
 * The CMS sends a template only while its digest matches the email's blocks;
 * until the next build lands (an edit schedules one) it sends the blocks in
 * its own layout, so an email never waits on the site.
 *
 *   // astro.config.mjs
 *   import { defineConfig } from "astro/config";
 *   import { cms } from "./src/lib/cms/integration";
 *   export default defineConfig({ integrations: [cms()] });
 */

import { readdir, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { CmsEmailBlock, CmsForm, CmsFormEmail } from "./types";

/** The meta tag the digest goes in; the integration reads it back. */
export const DIGEST_META = "cms-email-digest";

const KINDS: CmsFormEmail["kind"][] = ["notification", "confirmation"];

/**
 * getStaticPaths for the email route: one page per form and kind, with the
 * form and the email as props. Every form, published or not, so a draft
 * form's emails are ready when it goes live.
 */
export async function emailTemplatePaths() {
  const { cms } = await import("./cms");
  const forms = await cms.forms.list();
  const perForm = await Promise.all(
    forms.map(async (form: CmsForm) => {
      const emails = await cms.forms.emails(form.slug);
      return emails.map((email) => ({ params: { form: form.slug, kind: email.kind }, props: { form, email } }));
    }),
  );
  return perForm.flat();
}

/** Spread onto a <meta> in the template's <head>. */
export function digestMeta(email: CmsFormEmail) {
  return { name: DIGEST_META, content: email.content_digest };
}

/**
 * Spread onto the one row (a <tr>, usually) the CMS repeats per answer. Put
 * {{answer.label}} and {{answer.value}} inside it; they're filled, escaped,
 * for each field in the form's order.
 */
export function answersRow(block: Extract<CmsEmailBlock, { type: "email_submission" }>) {
  return {
    "data-cms-repeat": "answers",
    ...(block.data.skip_empty ? { "data-cms-skip-empty": "true" } : {}),
  };
}

interface Options {
  /** Where the email route builds to, under the output directory. */
  route?: string;
  /** Keep the built templates in the deployed site (they're only for the CMS). */
  keep?: boolean;
}

/**
 * The Astro integration: after `astro build`, sends each template under
 * `dist/<route>/<form>/<kind>` to the CMS (PUT
 * /api/forms/:form/emails/:kind/template). Needs CMS_BASE_URL and a
 * CMS_API_TOKEN with `forms:templates`. A failed send fails the build, so a
 * site never deploys believing its emails are current when they aren't.
 */
export function cmsEmailTemplates({ route = "emails", keep = false }: Options = {}) {
  return {
    name: "cms-email-templates",
    hooks: {
      "astro:build:done": ({ dir, logger }: { dir: URL; logger: Logger }) => sendEmailTemplates({ dir, route, keep, logger }),
    },
  };
}

interface Logger { info(message: string): void; warn(message: string): void }

/**
 * Sends each built template under `dir/<route>` to the CMS, then (unless
 * `keep`) removes them from the output. The `cms()` integration calls this;
 * `cmsEmailTemplates()` is it on its own.
 */
export async function sendEmailTemplates({ dir, route = "emails", keep = false, logger }: { dir: URL; route?: string; keep?: boolean; logger: Logger }) {
  const root = join(fileURLToPath(dir), route);
  const templates = await findTemplates(root);
  if (templates.length === 0) {
    logger.info(`No form email templates under ${route}/ (add src/pages/${route}/[form]/[kind].astro to design them).`);
    return;
  }

  const { cms } = await import("./cms");
  for (const { form, kind, file } of templates) {
    const html = await readFile(file, "utf8");
    const digest = readDigest(html);
    if (!digest) throw new Error(`${file} has no <meta name="${DIGEST_META}">; add digestMeta(email) to its <head>.`);

    const { status } = await cms.forms.sendEmailTemplate(form, kind, { html, digest });
    logger.info(`${form} ${kind} email → CMS (${status})`);
  }

  if (!keep) await rm(root, { recursive: true, force: true });
}

// <form>/<kind>/index.html (build.format "directory") or <form>/<kind>.html ("file").
async function findTemplates(root: string) {
  let forms: string[];
  try {
    forms = await readdir(root);
  } catch {
    return [];
  }

  const found: { form: string; kind: CmsFormEmail["kind"]; file: string }[] = [];
  for (const form of forms) {
    let entries: string[];
    try {
      entries = await readdir(join(root, form));
    } catch {
      continue;
    }
    for (const kind of KINDS) {
      if (entries.includes(kind)) found.push({ form, kind, file: join(root, form, kind, "index.html") });
      else if (entries.includes(`${kind}.html`)) found.push({ form, kind, file: join(root, form, `${kind}.html`) });
    }
  }
  return found;
}

function readDigest(html: string): string | null {
  const tag = html.match(new RegExp(`<meta[^>]+name=["']${DIGEST_META}["'][^>]*>`, "i"))?.[0];
  return tag?.match(/content=["']([^"']+)["']/i)?.[1] ?? null;
}

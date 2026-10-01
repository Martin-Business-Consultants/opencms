// Example: src/pages/api/cms/webhook.ts
// Receives outbound CMS webhooks. The handler verifies the signature and
// dispatches by event name.
//
// On Netlify, ISR / on-demand revalidation is built in — call
// `purgeData(["/path"])` from `@netlify/functions`. On Vercel, hit
// `revalidatePath`. Adapt the dispatch table to whatever your hosting
// platform exposes.

import type { APIRoute } from "astro";
import { handleWebhook } from "~/lib/cms/webhook-handler";

// Stub: replace with a real cache-purge / rebuild trigger.
async function revalidate(path: string) {
  console.info(`[cms] revalidate ${path}`);
  // Example for Netlify on-demand:
  // await fetch(`https://api.netlify.com/build_hooks/${process.env.NETLIFY_HOOK_ID}`, { method: "POST" });
}

async function revalidateAll() {
  console.info(`[cms] revalidate all`);
}

export const POST: APIRoute = ({ request }) =>
  handleWebhook(request, {
    "page.published":   ({ data }) => revalidate(`/${data.path}`),
    "page.updated":     ({ data }) => revalidate(`/${data.path}`),
    "page.unpublished": ({ data }) => revalidate(`/${data.path}`),
    "page.deleted":     ({ data }) => revalidate(`/${data.path}`),

    "entry.published":   ({ data }) => revalidate(`/${data.collection_slug}/${data.slug}`),
    "entry.updated":     ({ data }) => revalidate(`/${data.collection_slug}/${data.slug}`),
    "entry.unpublished": ({ data }) => revalidate(`/${data.collection_slug}/${data.slug}`),
    "entry.deleted":     ({ data }) => revalidate(`/${data.collection_slug}/${data.slug}`),

    "global.updated":   () => revalidateAll(),
  });

/**
 * Glue between this CMS's `/api/sitemap` and `@astrojs/sitemap`. Two ways
 * to use it:
 *
 *   1. Build-time prefetch (recommended for static / SSG):
 *
 *        // src/pages/sitemap.xml.ts
 *        import { sitemapXmlResponse } from "~/lib/cms/sitemap";
 *        export const GET = () => sitemapXmlResponse();
 *
 *   2. Augment @astrojs/sitemap so its filter knows about CMS-managed
 *      paths (useful when you want the sitemap to combine static and
 *      CMS routes):
 *
 *        // astro.config.mjs
 *        import { cmsSitemapFilter } from "./src/lib/cms/sitemap";
 *        export default defineConfig({
 *          integrations: [sitemap({ filter: await cmsSitemapFilter() })],
 *        });
 */

import { sitemap as fetchSitemap } from "./cms";
import type { CmsSitemap, CmsSitemapEntry } from "./types";

/** Pull the sitemap from the CMS and serve it directly as XML. */
export async function sitemapXmlResponse(): Promise<Response> {
  const data = await fetchSitemap();
  const xml  = renderXml(data);
  return new Response(xml, {
    status:  200,
    headers: {
      "Content-Type":  "application/xml; charset=utf-8",
      "Cache-Control": "public, max-age=300, s-maxage=600",
    },
  });
}

/**
 * Returns a `filter(page)` predicate suitable for `@astrojs/sitemap`'s
 * config. Anything the CMS knows about is allowed through; pages NOT
 * in the CMS are also allowed through (they're presumably handled by
 * other Astro routes). The CMS's own admin surface and any record
 * marked noindex is filtered out.
 */
export async function cmsSitemapFilter() {
  const data = await fetchSitemap();
  const noindexed = new Set(
    data.entries.filter((e) => e.noindex).map((e) => normalize(e.url)),
  );

  return (url: string) => !noindexed.has(normalize(url));
}

function normalize(url: string): string {
  try {
    return new URL(url).pathname.replace(/\/$/, "");
  } catch {
    return url.replace(/\/$/, "");
  }
}

function renderXml(data: CmsSitemap): string {
  const urls = data.entries.map(renderEntry).join("\n");
  return [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"`,
    `        xmlns:xhtml="http://www.w3.org/1999/xhtml">`,
    urls,
    `</urlset>`,
  ].join("\n");
}

function renderEntry(e: CmsSitemapEntry): string {
  const lines = [
    `  <url>`,
    `    <loc>${escape(e.url)}</loc>`,
    e.lastmod ? `    <lastmod>${e.lastmod}</lastmod>` : "",
    `    <changefreq>${e.changefreq}</changefreq>`,
    `    <priority>${e.priority.toFixed(2)}</priority>`,
    ...e.alternates.map(
      (a) => `    <xhtml:link rel="alternate" hreflang="${a.locale}" href="${escape(a.loc)}"/>`,
    ),
    `  </url>`,
  ];
  return lines.filter(Boolean).join("\n");
}

function escape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

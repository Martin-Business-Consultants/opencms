// Example: src/pages/sitemap.xml.ts
// Proxies the CMS's pre-built sitemap as the public-facing sitemap.xml.
import type { APIRoute } from "astro";
import { sitemapXmlResponse } from "~/lib/cms/sitemap";

export const GET: APIRoute = () => sitemapXmlResponse();

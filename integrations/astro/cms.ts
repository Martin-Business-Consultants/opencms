/**
 * Typed client for the CMS API. One thin wrapper per resource — no
 * caching layer, no retry loop. Lift those into your build pipeline if
 * you need them; this file exists to give you typed bindings, not
 * runtime infrastructure.
 *
 * Usage:
 *
 *   import { cms } from "~/lib/cms/cms";
 *   const page = await cms.pages.get("about");
 *   const posts = await cms.collections.entries("blog", { status: "published" });
 *
 * Errors throw `CmsError` with the underlying status + structured body.
 */

import type {
  CmsAsset,
  CmsCollection,
  CmsCollectionEntry,
  CmsForm,
  CmsFormEmail,
  CmsGlobal,
  CmsPage,
  CmsSitemap,
} from "./types";

const BASE_URL = readEnv("CMS_BASE_URL");
const TOKEN    = readEnv("CMS_API_TOKEN");

function readEnv(name: string): string {
  // Astro / Vite expose env vars on `import.meta.env`. Fall back to
  // `process.env` so this file is also usable from a Node script
  // (e.g., a build step that prefetches content).
  const fromMeta = (import.meta as { env?: Record<string, string> }).env?.[name];
  const fromNode = typeof process !== "undefined" ? process.env?.[name] : undefined;
  const value = fromMeta ?? fromNode;
  if (!value) {
    throw new Error(`Missing env var ${name}. Set it in .env or your hosting provider.`);
  }
  return value;
}

export class CmsError extends Error {
  constructor(
    public readonly status: number,
    public readonly path: string,
    public readonly body: unknown,
  ) {
    super(`CMS ${path} → ${status}`);
    this.name = "CmsError";
  }
}

interface FetchOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  query?: Record<string, string | number | undefined | null>;
  /** Pass `signal` from a `getStaticPaths` AbortController to cancel mid-build. */
  signal?: AbortSignal;
}

async function request<T>(path: string, opts: FetchOptions = {}): Promise<T> {
  const url = new URL(path.startsWith("http") ? path : `${BASE_URL}${path}`);
  if (opts.query) {
    for (const [k, v] of Object.entries(opts.query)) {
      if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
    }
  }

  const res = await fetch(url, {
    method:  opts.method ?? "GET",
    headers: {
      "Authorization": `Bearer ${TOKEN}`,
      "Accept":        "application/json",
      ...(opts.body ? { "Content-Type": "application/json" } : {}),
    },
    body:    opts.body ? JSON.stringify(opts.body) : undefined,
    signal:  opts.signal,
  });

  if (!res.ok) {
    let body: unknown;
    try { body = await res.json(); } catch { body = await res.text(); }
    throw new CmsError(res.status, path, body);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

// ── Pages ────────────────────────────────────────────────────────────────

interface PagesIndexResponse {
  pages: Pick<CmsPage, "id" | "slug" | "path" | "title" | "status" | "locale" | "tags" | "published_at" | "updated_at">[];
  page: number;
  per: number;
  total: number;
}

export const pages = {
  list: (params: { status?: CmsPage["status"]; locale?: string; page?: number; per?: number } = {}) =>
    request<PagesIndexResponse>("/api/pages", { query: params }),

  get: async (slugOrPath: string): Promise<CmsPage> => {
    const { page } = await request<{ page: CmsPage }>(`/api/pages/${encodeURIComponent(slugOrPath)}`);
    return page;
  },
};

// ── Collections ──────────────────────────────────────────────────────────

interface CollectionsIndexResponse {
  collections: CmsCollection[];
}

interface EntriesIndexResponse {
  collection: string;
  entries: Pick<CmsCollectionEntry, "id" | "slug" | "title" | "status" | "locale" | "tags" | "published_at" | "updated_at">[];
  page: number;
  per: number;
  total: number;
}

export const collections = {
  list: () => request<CollectionsIndexResponse>("/api/collections").then((r) => r.collections),

  get: async (slug: string): Promise<CmsCollection> => {
    const { collection } = await request<{ collection: CmsCollection }>(`/api/collections/${encodeURIComponent(slug)}`);
    return collection;
  },

  entries: (
    collectionSlug: string,
    params: { status?: CmsCollectionEntry["status"]; page?: number; per?: number } = {},
  ) =>
    request<EntriesIndexResponse>(
      `/api/collections/${encodeURIComponent(collectionSlug)}/entries`,
      { query: params },
    ),

  entry: async (
    collectionSlug: string,
    entrySlug: string,
  ): Promise<CmsCollectionEntry> => {
    const { entry } = await request<{ entry: CmsCollectionEntry }>(
      `/api/collections/${encodeURIComponent(collectionSlug)}/entries/${encodeURIComponent(entrySlug)}`,
    );
    return entry;
  },
};

// ── Globals ──────────────────────────────────────────────────────────────

export const globals = {
  list: () => request<{ globals: CmsGlobal[] }>("/api/globals").then((r) => r.globals),

  get: async (slug: string): Promise<CmsGlobal> => {
    const { global } = await request<{ global: CmsGlobal }>(`/api/globals/${encodeURIComponent(slug)}`);
    return global;
  },
};

// ── Forms ────────────────────────────────────────────────────────────────

export const forms = {
  list: () => request<{ forms: CmsForm[] }>("/api/forms").then((r) => r.forms),

  get: async (slug: string): Promise<CmsForm> => {
    const { form } = await request<{ form: CmsForm }>(`/api/forms/${encodeURIComponent(slug)}`);
    return form;
  },

  /** A form's notification and confirmation emails, as blocks. */
  emails: (slug: string) =>
    request<{ emails: CmsFormEmail[] }>(`/api/forms/${encodeURIComponent(slug)}/emails`).then((r) => r.emails),

  /**
   * Hands the CMS the template the build made of an email's blocks. `digest`
   * is the email's `content_digest` it was built from. Needs a token with
   * `forms:templates`. emails.ts's integration calls this for you.
   */
  sendEmailTemplate: (slug: string, kind: CmsFormEmail["kind"], template: { html: string; digest: string }) =>
    request<{ status: "current" | "stale"; content_digest: string }>(
      `/api/forms/${encodeURIComponent(slug)}/emails/${kind}/template`,
      { method: "PUT", body: template },
    ),
};

// ── Assets ───────────────────────────────────────────────────────────────

export const assets = {
  list: (params: { q?: string; page?: number; per?: number } = {}) =>
    request<{ assets: CmsAsset[]; pagination: { page: number; per: number; total: number; total_pages: number } }>(
      "/api/assets",
      { query: params },
    ),

  get: (id: string | number) => request<CmsAsset>(`/api/assets/${id}`),

  /**
   * Resolves the asset URL to an absolute one — useful for OpenGraph
   * images and other places where a relative path won't survive.
   */
  absoluteUrl: (asset: CmsAsset): string =>
    asset.url.startsWith("http") ? asset.url : `${BASE_URL}${asset.url}`,
};

// ── Sitemap ──────────────────────────────────────────────────────────────

export const sitemap = () => request<CmsSitemap>("/api/sitemap");

// ── Manifest (introspection) ─────────────────────────────────────────────

export const manifest = () => request<unknown>("/api/manifest");

// ── Aggregate export ─────────────────────────────────────────────────────

export const cms = { pages, collections, globals, forms, assets, sitemap, manifest };

/**
 * Type definitions matching the shapes the CMS returns from
 * /api/pages, /api/collections, /api/globals, /api/assets, /api/sitemap,
 * and the body of outbound webhooks.
 *
 * Adapt these to fit your project — adding custom block types or
 * frontmatter fields means widening the `data` / `frontmatter` shapes
 * here. Keep narrowing by `type` / event name where you can: it makes
 * components type-safe at the call site rather than at the boundary.
 */

export type CmsStatus = "draft" | "published" | "archived";

/** Reference fields use this shape for asset/page/entry refs. */
export type CmsLink =
  | { kind: "url"; value: string }
  | { kind: "entry"; collection: string; value: string }
  | { kind: "page"; value: string }
  | { kind: "asset"; value: string };

export interface CmsBlock {
  id?: string;
  type: string;
  version: number;
  data: Record<string, unknown>;
  /**
   * Some block types (collection_list, contact_info) come back with a
   * pre-resolved `resolved` field so consumers don't have to make a
   * second round-trip per block.
   */
  resolved?: Record<string, unknown>;
}

export interface CmsSeo {
  meta_title?: string;
  meta_description?: string;
  canonical?: string;
  noindex?: boolean;
  nofollow?: boolean;
  og_title?: string;
  og_description?: string;
  og_type?: string;
  twitter_card?: string;
  schema_type?: string;
  sitemap_priority?: number;
  sitemap_changefreq?: string;
}

export interface CmsPage {
  id: number;
  slug: string;
  path: string;
  parent_id: number | null;
  depth: number;
  title: string;
  status: CmsStatus;
  locale: string;
  tags: string[];
  blocks: CmsBlock[];
  frontmatter: Record<string, unknown>;
  seo: CmsSeo;
  published_at: string | null;
  publish_at: string | null;
  unpublish_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface CmsCollection {
  slug: string;
  name: string;
  schema: { fields: CmsField[] };
  frontmatter_json_schema: object;
  entry_count: number;
}

export interface CmsCollectionEntry {
  id: number;
  slug: string;
  collection_slug: string;
  title: string;
  status: CmsStatus;
  locale: string;
  tags: string[];
  frontmatter: Record<string, unknown>;
  body_markdown: string;
  seo: CmsSeo;
  published_at: string | null;
  publish_at: string | null;
  unpublish_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface CmsGlobal {
  slug: string;
  name: string;
  description: string | null;
  fields: CmsField[];
  data: Record<string, unknown>;
}

export interface CmsAsset {
  id: number;
  name: string | null;
  folder: string;
  filename: string;
  content_type: string;
  byte_size: number;
  url: string;
  alt: string | null;
  caption: string | null;
  description: string | null;
  focal_x: number;
  focal_y: number;
  /** Pre-baked responsive sources. Empty for non-image assets. */
  srcset: { width: number; descriptor: string; url: string }[];
  created_at: string;
}

export interface CmsField {
  name: string;
  label?: string;
  type: string;
  required?: boolean;
  options?: { value: string; label: string }[];
  of?: CmsField[];
  of_collection?: string;
}

export interface CmsSitemapEntry {
  source: "page" | "collection_entry";
  id: number;
  title: string;
  loc: string;
  url: string;
  lastmod: string | null;
  changefreq: string;
  priority: number;
  status: CmsStatus;
  noindex: boolean;
  nofollow: boolean;
  locale: string;
  alternates: { locale: string; loc: string }[];
  collection_slug: string | null;
  slug: string;
  included: boolean;
}

export interface CmsSitemap {
  generated_at: string;
  site_base_url: string;
  count: number;
  entries: CmsSitemapEntry[];
}

// ── Forms and their emails ───────────────────────────────────────────────

export interface CmsFormField {
  name: string;
  label: string;
  type: "text" | "email" | "tel" | "url" | "textarea" | "select" | "radio" | "checkbox" | "file";
  required?: boolean;
  placeholder?: string;
  help?: string;
  options?: { value: string; label: string }[];
}

export interface CmsForm {
  id: number;
  slug: string;
  title: string;
  status: CmsStatus;
  fields: CmsFormField[];
  submit_label: string;
  success_message: string | null;
}

/**
 * The blocks a form email is built from. Every string (and the text block's
 * HTML) may hold {{tokens}} — {{form_title}}, {{submission_id}},
 * {{submitted_at}}, {{ip}} or a field's name. Leave them in: the CMS fills
 * them per submission. See emails.ts.
 */
export type CmsEmailBlock =
  | { id?: string; type: "email_heading"; version: number; data: { text: string; level?: "h1" | "h2" | "h3"; align?: "left" | "center" } }
  | { id?: string; type: "email_text"; version: number; data: { body: string } }
  | { id?: string; type: "email_button"; version: number; data: { label: string; url: string; align?: "left" | "center" } }
  | { id?: string; type: "email_image"; version: number; data: { asset: string; alt?: string; url?: string; align?: "left" | "center" }; resolved?: { url: string | null } }
  | { id?: string; type: "email_submission"; version: number; data: { title?: string; skip_empty?: boolean } }
  | { id?: string; type: "email_divider"; version: number; data: Record<string, never> }
  | { id?: string; type: "email_spacer"; version: number; data: { size?: "small" | "medium" | "large" } };

export interface CmsFormEmail {
  id: number;
  kind: "notification" | "confirmation";
  enabled: boolean;
  subject: string;
  blocks: CmsEmailBlock[];
  /** Stamp this into the template you build (emails.ts: `digestMeta`). */
  content_digest: string;
  site_template: { status: "current" | "stale" | "none"; received_at: string | null };
}

// ── Webhook envelope ─────────────────────────────────────────────────────

export type CmsWebhookEvent =
  | "page.published"
  | "page.updated"
  | "page.unpublished"
  | "page.deleted"
  | "entry.published"
  | "entry.updated"
  | "entry.unpublished"
  | "entry.deleted"
  | "global.updated";

export interface CmsWebhookPayload<E extends CmsWebhookEvent = CmsWebhookEvent> {
  event: E;
  /** The CMS install's site key (Site.key). Named `tenant` for compatibility. */
  tenant: string;
  delivered_at: string;
  /**
   * Per-event payload. Pages carry { id, slug, path, title, status, locale,
   * published_at, updated_at }; entries add `collection_slug`; globals
   * carry { slug, name, updated_at }. Test deliveries include `{ test: true }`.
   */
  data: Record<string, unknown>;
}

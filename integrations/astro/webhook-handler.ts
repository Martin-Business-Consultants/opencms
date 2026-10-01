/**
 * Astro endpoint helper for receiving CMS webhooks. Signature
 * verification is mandatory: the CMS signs every delivery body with
 * HMAC-SHA256 using the webhook's `Signing secret`, and the value
 * arrives in `X-CMS-Signature` as `sha256=<hex>`.
 *
 * Usage (recommended path: src/pages/api/cms/webhook.ts):
 *
 *   import type { APIRoute } from "astro";
 *   import { handleWebhook } from "~/lib/cms/webhook-handler";
 *
 *   export const POST: APIRoute = ({ request }) =>
 *     handleWebhook(request, {
 *       "page.published": ({ data }) => revalidate(`/${data.path}`),
 *       "global.updated": () => revalidateAll(),
 *     });
 *
 * Handlers can be async; `handleWebhook` awaits them in serial. Throwing
 * from a handler returns a 500 to the CMS so the delivery is recorded
 * as failed (and retried per the CMS retry policy). Unknown event
 * names are logged and silently 200'd — adding a new event to the CMS
 * shouldn't take the consumer down.
 */

import type { CmsWebhookEvent, CmsWebhookPayload } from "./types";

const SECRET = readEnv("CMS_WEBHOOK_SECRET");

function readEnv(name: string): string {
  const fromMeta = (import.meta as { env?: Record<string, string> }).env?.[name];
  const fromNode = typeof process !== "undefined" ? process.env?.[name] : undefined;
  const value = fromMeta ?? fromNode;
  if (!value) {
    throw new Error(`Missing env var ${name}. Set it in .env or your hosting provider.`);
  }
  return value;
}

export type WebhookHandler<E extends CmsWebhookEvent = CmsWebhookEvent> = (
  payload: CmsWebhookPayload<E>,
) => unknown | Promise<unknown>;

export type WebhookHandlerMap = Partial<{ [K in CmsWebhookEvent]: WebhookHandler<K> }>;

export interface HandleWebhookOptions {
  /** Override the env-var secret if you need to (e.g. multi-tenant routing). */
  secret?: string;
  /** Log non-fatal issues somewhere other than console. */
  log?: (message: string, extra?: unknown) => void;
}

/**
 * Verify the signature, parse the body, dispatch by event, and return
 * an Astro-compatible Response. Always reads the body as text so the
 * signature check matches the bytes the CMS hashed.
 */
export async function handleWebhook(
  request: Request,
  handlers: WebhookHandlerMap,
  opts: HandleWebhookOptions = {},
): Promise<Response> {
  const log = opts.log ?? ((m, extra) => console.warn(`[cms-webhook] ${m}`, extra ?? ""));
  const provided = request.headers.get("X-CMS-Signature");
  if (!provided) {
    return json({ error: "missing_signature" }, 401);
  }

  const body = await request.text();
  const expected = await sign(body, opts.secret ?? SECRET);
  if (!constantTimeEqual(provided, expected)) {
    log("signature mismatch", { provided });
    return json({ error: "invalid_signature" }, 401);
  }

  let payload: CmsWebhookPayload;
  try {
    payload = JSON.parse(body) as CmsWebhookPayload;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const handler = handlers[payload.event] as WebhookHandler | undefined;
  if (!handler) {
    log(`unhandled event ${payload.event}`);
    return json({ ok: true, ignored: payload.event });
  }

  try {
    await handler(payload);
    return json({ ok: true });
  } catch (err) {
    log(`handler threw for ${payload.event}`, err);
    return json({ error: "handler_failed", message: (err as Error).message }, 500);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sign(body: string, secret: string): Promise<string> {
  // Web Crypto in Astro / Node 20+ — avoids a `node:crypto` dependency
  // so the same handler runs in browser-edge runtimes too.
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(body));
  return "sha256=" + bufferToHex(sig);
}

function bufferToHex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Length-stable comparison so timing tells the attacker nothing. */
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

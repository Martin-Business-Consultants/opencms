/**
 * The CMS integration for an Astro site: one line in astro.config and the
 * site is ready to work with the headless CMS.
 *
 *   // astro.config.mjs
 *   import { defineConfig } from "astro/config";
 *   import { cms } from "./src/lib/cms/integration";
 *   export default defineConfig({ integrations: [cms()] });
 *
 * With CMS_BASE_URL and CMS_API_TOKEN in the environment (or .env), on every
 * `astro dev` and `astro build` it:
 *
 *   - writes the CMS's frontend guide into AGENTS.md at the project root,
 *     between its markers (the rest of the file is left alone), and a
 *     CLAUDE.md that points at it when there isn't one — so an AI working in
 *     this repo knows content comes from the CMS and how to read it;
 *   - saves the content model (GET /api/manifest) to .cms/manifest.json, so
 *     components are written against real field and block names;
 *
 * and after `astro build`:
 *
 *   - sends the form email templates the build made (emails.ts);
 *   - tells the CMS the build ran (POST /api/frontend/builds), which its
 *     Developers screen and dashboard show.
 *
 * Without the two variables, `astro dev` warns and carries on; `astro build`
 * stops, since it can't fetch content anyway.
 */

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnv } from "vite";
import { sendEmailTemplates } from "./emails";

export const INTEGRATION_NAME = "librepublish-cms";
export const INTEGRATION_VERSION = "1.0.0";

const START = "<!-- librepublish:cms-frontend -->";
const END = "<!-- /librepublish:cms-frontend -->";

interface Options {
  /** Write the frontend guide into AGENTS.md (and a CLAUDE.md pointing at it). */
  agentsMd?: boolean;
  /** Save the content model to .cms/manifest.json. */
  manifest?: boolean;
  /** Send the form email templates after a build. */
  emails?: boolean;
  /** Where the email route builds to, and whether to keep it in the deployed site. */
  emailRoute?: string;
  keepEmails?: boolean;
  /** Report each build to the CMS. */
  report?: boolean;
}

interface Logger { info(message: string): void; warn(message: string): void }
interface Connection { baseUrl: string; token: string }

export function cms(options: Options = {}) {
  const { agentsMd = true, manifest = true, emails = true, emailRoute = "emails", keepEmails = false, report = true } = options;
  let root = "";
  let site: string | undefined;
  let startedAt = 0;

  return {
    name: INTEGRATION_NAME,
    hooks: {
      "astro:config:setup": async ({ config, command, logger }: { config: { root: URL; site?: string }; command: string; logger: Logger }) => {
        root = fileURLToPath(config.root);
        site = config.site;
        startedAt = Date.now();

        const connection = connect(root, command);
        if (!connection) {
          const message = "CMS_BASE_URL and CMS_API_TOKEN aren't set (in the environment or .env), so the site can't read the CMS.";
          if (command === "build") throw new Error(message);
          logger.warn(message);
          return;
        }

        await Promise.all([
          agentsMd && writeAgentsMd(root, connection, logger),
          manifest && writeManifest(root, connection, logger),
        ]);
      },

      "astro:build:done": async ({ dir, pages, logger }: { dir: URL; pages: unknown[]; logger: Logger }) => {
        const connection = connect(root, "build");
        if (!connection) return;

        if (emails) await sendEmailTemplates({ dir, route: emailRoute, keep: keepEmails, logger });
        if (report) await reportBuild(root, connection, { pages: pages.length, site_url: site, duration_ms: Date.now() - startedAt }, logger);
      },
    },
  };
}

// CMS_BASE_URL and CMS_API_TOKEN from the environment or the project's .env
// files (Astro loads those for the site's code, not for its config), put in
// process.env so cms.ts finds them too.
function connect(root: string, command: string): Connection | null {
  const env = loadEnv(command === "dev" ? "development" : "production", root, "CMS_");
  for (const [name, value] of Object.entries(env)) process.env[name] ??= value;

  const baseUrl = process.env.CMS_BASE_URL?.replace(/\/+$/, "");
  const token = process.env.CMS_API_TOKEN;
  return baseUrl && token ? { baseUrl, token } : null;
}

async function cmsFetch(connection: Connection, path: string, init: RequestInit = {}) {
  const response = await fetch(`${connection.baseUrl}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${connection.token}`, Accept: "application/json", ...(init.body ? { "Content-Type": "application/json" } : {}) },
  });
  if (!response.ok) throw new Error(`CMS ${init.method ?? "GET"} ${path} → ${response.status}`);
  return response;
}

// The guide goes between its markers; anything else in AGENTS.md stays.
async function writeAgentsMd(root: string, connection: Connection, logger: Logger) {
  let guide: string;
  try {
    guide = (await (await fetch(`${connection.baseUrl}/frontend/AGENTS.md`)).text()).trim();
  } catch (error) {
    logger.warn(`Couldn't fetch the CMS's frontend guide: ${(error as Error).message}`);
    return;
  }
  if (!guide.startsWith(START)) guide = `${START}\n${guide}\n${END}`;
  if (!guide.includes(END)) guide = `${guide}\n${END}`;

  const file = join(root, "AGENTS.md");
  const current = await readFile(file, "utf8").catch(() => "");
  const start = current.indexOf(START);
  const end = current.indexOf(END);
  const next = start >= 0 && end > start
    ? current.slice(0, start) + guide + current.slice(end + END.length)
    : current.trim() ? `${current.trimEnd()}\n\n${guide}\n` : `${guide}\n`;

  if (next !== current) {
    await writeFile(file, next);
    logger.info("AGENTS.md: the CMS frontend guide is up to date");
  }

  // Claude Code reads CLAUDE.md, which can import AGENTS.md.
  const claude = join(root, "CLAUDE.md");
  if (!(await readFile(claude, "utf8").catch(() => null))) await writeFile(claude, "@AGENTS.md\n");
}

async function writeManifest(root: string, connection: Connection, logger: Logger) {
  try {
    const manifest = await (await cmsFetch(connection, "/api/manifest")).json();
    await mkdir(join(root, ".cms"), { recursive: true });
    await writeFile(join(root, ".cms", "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
    logger.info(".cms/manifest.json: the CMS content model is up to date");
  } catch (error) {
    logger.warn(`Couldn't fetch the CMS content model: ${(error as Error).message}`);
  }
}

async function reportBuild(root: string, connection: Connection, build: { pages: number; site_url?: string; duration_ms: number }, logger: Logger) {
  const astro = JSON.parse(await readFile(join(root, "node_modules", "astro", "package.json"), "utf8").catch(() => "{}"));
  try {
    await cmsFetch(connection, "/api/frontend/builds", {
      method: "POST",
      body: JSON.stringify({
        integration: INTEGRATION_NAME, integration_version: INTEGRATION_VERSION,
        framework: "astro", framework_version: astro.version, ...build,
      }),
    });
    logger.info("Build reported to the CMS");
  } catch (error) {
    logger.warn(`Couldn't report the build to the CMS: ${(error as Error).message}`);
  }
}

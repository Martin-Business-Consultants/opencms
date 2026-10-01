---
title: "How this CMS works"
summary: "Headless, and made to be driven: the API, the cms CLI and MCP, and this admin for doing things by hand."
position: 1
---

This CMS keeps the content of **{{site}}** and serves it as JSON. It never
renders pages for visitors: the public site — an Astro app in its own repo —
fetches the JSON when it builds and renders it with its own components.

## Four ways in

| | For | How |
|---|---|---|
| **The API** | Sites, scripts, anything that speaks HTTP | `{{cms_url}}/api`, JSON, a bearer token |
| **The `cms` CLI** | People and agents in a terminal | `curl -fsSL {{cms_url}}/agent/install.sh \| sh` |
| **MCP** | Claude Code, and any MCP client | `claude mcp add cms -- cms mcp`, once the CLI is in |
| **This admin** | Doing things by hand | You're in it |

The CLI and MCP do everything the admin does to content, structure and
operations, and every screen here names its `cms` command under its title.
The API stands under all three.

## What's in it

- **Pages** — the site's pages, in a tree. Each is built from **blocks**
  (a hero, some text, a list of entries…) whose shapes are the site's
  **block types**, and can carry fields of its own.
- **Collections** — repeating content (posts, team members, specials), each
  with its own fields. An entry of one lives at `/<collection>/<slug>`.
- **Globals** — one-of-a-kind content the whole site shares: navigation,
  footer, contact details.
- **Media** — images and files, with alt text, captions and folders.
- Plugins add more: **forms** and their submissions and emails, **scripts**
  and the consent banner, quotes and invoices, agents, reports.

Every page, entry and global has a **JSON** tab in its editor: exactly what
the site receives for it.

## Publishing

A record is a **draft** until it's **published**; only published content
reaches the site. Publishing takes the publish capability — someone without
it asks for a review instead, and a change they make to something already
live waits in **Approvals** until someone who can publish accepts it. Agents
work the same way: the Agent role writes but never publishes.

Publishing triggers a rebuild of the site (Settings › Deploy), so a change
goes live a minute or two later. Scheduled publishing does the same at its
time.

## Where to go next

- [Working with an Astro site](/docs/astro)
- [Working with AI](/docs/ai)
- [Before going live](/docs/go-live)

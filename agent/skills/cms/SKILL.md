---
name: cms
description: >
  Read and write content in a LibrePublish CMS with the `cms` CLI, and
  work on the Astro site it publishes. Use whenever the user asks you to look at
  or change site content (pages, collection entries, globals, redirects), to
  manage the site's forms, webhooks, deploys, schedules or backups, to find
  where something on the site comes from, or to work on the site repo paired
  with a CMS. Assumes `cms` is installed — if it isn't, install it with
  `curl -fsSL __CMS_URL__/agent/install.sh | sh`.
---

# Working with a LibrePublish CMS

The CMS holds the content; a separate Astro repo holds the site that renders it.
Content changes go through the `cms` CLI (a thin wrapper over the CMS's HTTP
API); template and layout changes go through the repo, as a normal PR.

The CLI covers the same ground as the admin UI — content, schemas, forms,
redirects, webhooks, deploys, trash, review, audit, backups. If a task seems to
need a human in a browser, check `cms commands --json` first.

## Two flags worth knowing before anything else

`--agent` turns every answer into `{status, summary, data, breadcrumbs}`.
`summary` is the one line a person would say out loud; `breadcrumbs` are the
exact next commands, already filled in with the ids and paths that were just
returned. Use it for everything — it is how you learn the surface by using it
rather than by guessing at paths.

`cms commands --json` prints the whole surface in one call: every command, its
flags, and the traps. Read it once instead of discovering the CLI one usage
error at a time.

## Orient first

```sh
cms doctor      # can this machine actually work? what's stopping it?
cms whoami      # the user this token acts as + the capabilities it carries
cms manifest    # collections and their frontmatter schemas, block types and
                # their JSON schemas, globals, forms, brand brief, counts
cms brand       # just the brand brief — read before writing any copy
```

`cms doctor` is the first call on an unfamiliar machine. It answers the thing
nothing else can: whether the credential reaches the site, what the role
actually grants, and whether there is work queued. A role missing `agents:run`
polls forever and is handed nothing, which looks exactly like an empty queue —
doctor is what tells the two apart.

`cms manifest` is the single most useful call. It's the CMS describing its own
shape, so you can write a valid entry the first time instead of discovering the
schema through 422s.

`cms brand` is the workspace's own brief on voice, audience, facts that must
stay accurate, and house style. Copy that ignores it gets rewritten. If it's
empty, ask for a sentence on voice and audience rather than guessing.

The site repo is recorded in the CMS, as `frontend_github_repo` under the
`github` setting:

```sh
cms get /settings/github
```

If it comes back blank, ask the user for it and write it back — that's how the
next session avoids asking again:

```sh
cms patch /settings/github '{"setting":{"data":{"frontend_github_repo":"owner/name"}}}'
```

## Reading content

```sh
cms pages [--status published] [--locale en] [--page 2]
cms page <path>                 # one page, blocks + assets expanded
cms collections
cms collection <slug>
cms entries <collection> [--status draft]
cms entry <collection> <slug>
cms globals | cms global <slug>
cms blocks                      # available block types
cms forms | cms assets | cms sitemap
cms search "<query>"
cms refs <ref_type> <ref_id>    # inverse lookup: what points at this record
```

Everything prints JSON — pretty-printed for reading, compact under `--agent`,
and exactly as the server sent it under `--raw`.

## Writing content

Writes need the matching capability on the user's role — `pages:write`,
`entries:write`, `pages:publish`, and so on.

```sh
cms post  /pages '{"page":{"slug":"pricing","title":"Pricing","status":"draft","locale":"en"}}'
cms patch /pages/pricing '{"page":{"title":"Plans & pricing"}}'
cms post  /collections/posts/entries '{"entry":{"slug":"hello","title":"Hello","status":"draft"}}'
cms patch /collections/posts/entries/hello - < entry.json

cms publish pricing             # and: cms unpublish, cms status <status> <path...>
cms entry-status posts published hello
cms delete /pages/pricing       # → trash
```

Rules that keep this safe:

- **Create as `draft`** unless the user explicitly asked to publish. Publishing
  is world-visible and triggers a rebuild of the public site.
- **Match the schema from `cms manifest`.** A collection's `frontmatter_json_schema`
  is authoritative; a page's blocks must be types listed in `cms blocks`.
- **Read back what you wrote** (`cms page <path>`) before reporting it done.
- **Renaming a slug breaks inbound links.** Add the redirect in the same change:
  `cms redirect add /old-path /new-path 301`.

## Recovering

Deletes are soft. Nothing is lost until someone purges it.

```sh
cms trash                       # what's recoverable, and when it was deleted
cms restore page 12
cms purge page 12               # permanent — ask first
```

## Structure

Field schemas are editable. The payload is the field list; it replaces the
existing one rather than merging, so send the whole thing.

```sh
cms schema page       about/team < fields.json
cms schema collection posts      < fields.json
cms schema global     nav        < fields.json
cms seed-blocks                  # starter-pack blocks, only on an empty site
```

## Forms, redirects, webhooks

```sh
cms submissions [--form contact] [--since 2026-08-01]
cms submission 42
cms emails contact              # notification + confirmation templates
cms patch /forms/contact/emails/notification '{"form_email":{"enabled":true,"subject":"…","body":"…","recipients":"ops@example.com"}}'

cms redirects all
cms redirect add /old /new 301
cms redirects import < redirects.csv

cms webhooks
cms webhook test 3              # fire a synthetic delivery
```

## Commerce (quotes and invoices)

```sh
cms quotes --status new         # requests from the site's "Request a quote" button
cms quote 12
cms quote-status 12 quoted --notes "…"
cms invoice-create --from-quote 12 [--payment-link URL]
cms invoice 3                   # lines, totals, public_url for the customer
cms invoice-send 3              # needs invoices:send — a person's call
cms invoice-paid 3 · cms invoice-void 3
cms get /settings/commerce      # recipients, prefix, business details
```

Items on a quote are the product as the visitor saw it (title, SKU, listed
price, URL). An invoice's amounts are integer cents; `payment_link` is the
processor's URL — the CMS hosts the invoice page, it does not take the money.

## Shipping

```sh
cms deploy                      # hook config, last status, recent attempts
cms deploy now                  # trigger a rebuild
```

After publishing, `cms deploy` is how you find out whether the build actually
succeeded. "Published" and "live" are different claims — check before making the
second one.

## Operations

```sh
cms audit --actor ted --event page.published
cms schedules                   # recurring maintenance recipes
cms run-task trash_purge
cms backup > backup.tar.gz      # full site export before anything risky
```

Take a backup before a bulk edit or an import. It costs one command.

## Working the run queue

The CMS can hand you work rather than waiting to be asked. Someone defines an
**agent** in the UI — instructions, a slice of the site, a cadence — and the CMS
queues a **run**. It never executes one itself; that is what this machine is
for.

```sh
cms work --agent          # claim the next queued run and print its brief
                          # exit 3 = nothing queued, which is normal
cms run-start <id>
cms run-step <id> "audited 40 pages, 6 titles over length"
cms run-ping <id>         # every few minutes on a long run
cms run-done <id> "Rewrote 6 titles, filed 2 findings"
cms run-fail <id> "GSC export was empty — nothing to audit"
```

The brief is the job: `agent.instructions` (what to do), `scope` (what to do it
to), `capabilities` (the commands you may use), `rules` (non-negotiable). It is
snapshotted at queue time, so it will not shift under you.

Run the loop with `--agent` and you never have to remember the id: every reply
carries the next command with it already filled in.

Two things are easy to get wrong:

- **`run-ping` is a question, not a keepalive.** `"continue": false` means the
  run was canceled or reassigned while you worked. Stop there — carrying on
  spends tokens on a run someone else is redoing.
- **Always finish the run.** Abandoning one leaves it claimed until the lease
  lapses, and then another worker repeats everything you just did.

### Filing findings

Most SEO work is not an edit. A topic with demand and no page, two pages
competing for one query, a statistic that needs a human to confirm — none of
those have a record to change, and a run summary is where they go to die.

```sh
cms recommend content_gap "No page for 'pricing for teams'" \
  --body "Nothing covers it; /pricing links to a /teams that 404s." --impact 4
cms recommend metadata "Title is 94 characters" --subject page:/about/team
cms recommend cannibalization "Two pages target 'onboarding'" --subject posts:onboarding-guide
cms findings                    # what's already filed — don't duplicate it
```

Kinds: `content_gap` `metadata` `schema` `internal_linking` `cannibalization`
`technical` `freshness` `accessibility`. Set `CMS_AGENT_RUN_ID=<id>` and each
finding is attributed to the run that produced it.

Filing one is not making the change. A human accepting it records a decision;
the edit still goes through the ordinary write path and its review gate.

## Service tokens

Credentials for machines rather than people. A service token belongs to the
workspace and carries the role named on it, so rotating a person's token or
changing their role can't take the site down.

```sh
cms service-tokens                          # every token, plus the roles available
cms service-token create --name PRODUCTION --role "Production site"
cms service-token reveal 3                  # show the secret again
cms service-token rotate 3                  # new secret, old one dead immediately
cms service-token revoke 3
```

The published site runs on a **read-only** token issued against the **Production
site** role and stored in its environment as `PRODUCTION_TOKEN`. Yours is a
different one: `USER_AGENT_TOKEN`, on the **Agent** role, which writes but can't
publish. Issuing or revealing either needs `settings:write`.

The list carries no secrets — only prefixes and masks. `create`, `reveal` and
`rotate` each return one, once. Print it for the person who asked and stop
there.

## Working the site repo

```sh
gh repo clone <repo> && cd <repo>     # <repo> = frontend_github_repo, above
git switch -c <branch>
# …change templates/layout/components…
npm install && npm run build          # the minimum bar before a PR
gh pr create --fill
```

Keep the split honest: copy belongs in the CMS, structure belongs in the repo.
If a change could be made either way, prefer the one that leaves the other side
untouched.

## When something is refused

A `403` is the user's role talking: their account doesn't hold that capability.
Report it plainly — "your role doesn't grant `pages:publish`, so I left it as a
draft" — and don't look for a way around it.

If the work itself is finished and only the publish is blocked, don't just stop:

```sh
cms review request Page pricing "Copy is done, ready for a look"
```

That puts it in a human's queue instead of leaving it looking abandoned.

A `401` means the credential is stale. Reconnect — it takes a browser click and
no token is ever pasted anywhere:

```sh
cms login --url https://<site>
```

One machine can hold several identities (you and a service account, or two
sites). `cms profiles` lists them; `--profile <name>` or `CMS_PROFILE` picks one.

## Never

- Write `USER_AGENT_TOKEN` into `AGENTS.md`, the repo, or a commit. It lives in
  `~/.config/cms/<profile>.env`, mode 0600, and it belongs nowhere else.
- Write a service token secret anywhere either — not into a file, the site repo,
  a commit, or a message you leave behind. `PRODUCTION_TOKEN` goes straight into
  the host's environment settings and nowhere else.
- Present unverified work as done. If `npm run build` failed or you couldn't run
  it, say so and open the PR as a draft.
- Delete content to make an error go away. Ask.
- `cms purge` or `cms delete /tools/import/wipe` on your own initiative. Both are
  irreversible; both need the user to say so explicitly.

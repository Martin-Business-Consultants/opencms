<!-- librepublish:cms-agent -->
# Working with the __SITE__ CMS

This directory is wired to a LibrePublish CMS at __CMS_URL__. Content
lives in the CMS; the public site is an Astro app in its own GitHub repo. You
read and write content with the `cms` CLI, and you change the site itself the
normal way — clone, branch, PR.

Everything the CMS's own admin UI can do to content, structure and site
operations is reachable from `cms`. If you find yourself asking a human to go
click something, check `cms commands --json` first — it's probably there.

Two flags first, because they change how much of the rest you need to read:

- **`--agent`** wraps every answer as `{status, summary, data, breadcrumbs}`.
  The breadcrumbs are the next commands to run, already filled in with the ids
  and paths just returned — so the surface teaches itself as you use it.
- **`cms commands --json`** is the entire command set, with flags and traps, in
  one call. Cheaper than learning it one usage error at a time.

## Site repo

The repo is recorded in the CMS, not in this file — ask the CMS for it:

```sh
cms get /settings/github     # → data.frontend_github_repo, e.g. "acme/acme-site"
```

Do that before any task that touches the site itself (templates, layout,
styling, build config, anything that isn't content), then:

```sh
gh repo clone <frontend_github_repo> && cd <repo>
```

The site is the frontend of this headless CMS: it fetches content as JSON and
renders it. Its own `AGENTS.md` (written there by the CMS's Astro integration,
and at __CMS_URL__/frontend/AGENTS.md) explains how — the JSON shapes, blocks,
forms, previews and rebuilds. Read it before changing templates.

**If `frontend_github_repo` comes back blank, ask the user which Astro repo
this CMS publishes and write it back to the CMS** so no later session — yours
or another agent's — has to ask again:

```sh
cms patch /settings/github '{"setting":{"data":{"frontend_github_repo":"owner/name"}}}'
```

Store it as `owner/name`, not a URL. The `token` under that same key reads back
masked (`***abcd`) — that's deliberate, and it doesn't affect the repo field.

## The CMS

```sh
cms doctor      # can this machine work, and what's stopping it
cms whoami      # who this token acts as, and what it's allowed to do
cms manifest    # the shape of this CMS: collections, frontmatter schemas,
                # block types + their JSON schemas, globals, forms, brand, counts
cms commands    # everything else (add --json for the machine-readable form)
```

Start with `cms manifest`. It answers most structural questions in one call —
which collections exist, what fields their entries carry, which blocks a page
may be composed from — so you don't have to guess a schema and get a 422.

### Write in the workspace's voice

`cms brand` returns the brand brief the owners wrote: voice, audience, facts
that have to stay accurate, and house style rules. **Read it before you write
any copy.** It's the difference between prose that sounds like the site and
prose that has to be rewritten. If it's empty, ask the user for a sentence on
voice and audience rather than inventing one.

### Reading

```sh
cms pages                       # every page (add --status published, --locale en)
cms page about/team             # one page, blocks and assets expanded
cms collections
cms entries posts --status published
cms entry posts my-first-post
cms globals                     # nav, footer, scripts, …
cms search "pricing"
cms refs Page 12                # what links to this record
```

### Writing

```sh
cms post  /pages '{"page":{"slug":"pricing","title":"Pricing","status":"draft","locale":"en"}}'
cms patch /pages/pricing '{"page":{"title":"Plans & pricing"}}'
cms patch /collections/posts/entries/my-first-post - < entry.json

cms publish pricing about/team  # flip pages to published
cms unpublish pricing
cms entry-status posts published my-first-post
```

### Undo

Deletes go to the trash, not the void:

```sh
cms delete /pages/pricing       # → trash
cms trash                       # what's recoverable
cms restore page 12
cms purge page 12               # permanent, no undo
```

### Structure

Schemas are editable too — field definitions for a page, a collection's
entries, or a global:

```sh
cms schema collection posts < fields.json
cms seed-blocks                 # starter-pack block types, empty sites only
```

### Reporting

The CMS measures what search, Google Maps, reviews and the AI assistants show
about the business, as dated snapshots. You can read them; you cannot run
them — a run spends money and is a person's decision.

```sh
cms reports                       # every report's latest figures, and how they moved
cms report ranked_keywords        # one report in full
cms report ranked_keywords --previous   # the snapshot before, to compare
```

A finding that comes from a report should say which report, which date and
which figure — `cms recommend technical "Page health fell 84 → 61" --body
"page_health, 17 Sep: /prices returned 500 …" --impact 5`.

### Shipping and operations

```sh
cms deploy                      # hook config + whether the last build worked
cms deploy now                  # trigger a rebuild
cms redirects all               # every rule, with hit counts
cms redirect add /old /new 301
cms submissions                 # form inbox across every form
cms quotes --status new         # quote requests from the site's "Request a quote"
cms invoice-create --from-quote 12 --payment-link https://…   # then: cms invoice-send <id>
cms audit --actor ted           # who changed what
cms webhooks
cms backup > backup.tar.gz
```

Anything the curated commands don't cover is reachable with
`cms get|post|patch|delete <path>` — it's the same API the site build uses.

### Selling by quotation

A site that sells by quote rather than by cart posts its "Request a quote"
button to `POST /api/quote_requests` (unauthenticated, CORS like forms) with
the customer's details and the items as the visitor saw them. Those land in
the **quote inbox**; an **invoice** is what the shop sends back.

```sh
cms quotes --status new                 # the inbox
cms quote 12                            # items, message, staff notes, invoices so far
cms quote-status 12 quoted --notes "called, wants freight to Ohio"
cms invoice-create --from-quote 12      # a draft: customer + one line per item, at the listed price
cms patch /invoices/3 '{"invoice":{"line_items":[…],"shipping_cents":45000,"payment_link":"https://buy.stripe.com/…"}}'
cms invoice-send 3                      # emails the customer the hosted page and the payment link
cms invoice-paid 3                      # the quote behind it becomes won
```

The CMS never moves money: `payment_link` is whatever the shop's processor
issued. Sending needs `invoices:send`, which the Agent role does not hold —
draft the invoice, set the link, and leave the send to a person.
`cms get /settings/commerce` holds who is notified, the invoice prefix and
the business details printed on invoices.

### Writes to live content may come back as a revision

If your token's role doesn't hold the publish capability for what you're
editing (`pages:publish`, `entries:publish`, `globals:publish`), a write to a
record that is **already published** doesn't apply. It's filed as a revision
for a human to review, and you get **202** instead of 200:

```json
{"status": "pending_review",
 "revision": {"id": 41, "fields": ["title", "blocks"]},
 "review_url": "https://…/revisions/41"}
```

The live content is unchanged, and re-reading the record shows the old values —
that is the gate working, not your write failing. Report the review URL and
stop; don't retry, and don't try to reach the content another way. A second
proposal for the same record comes back **409** with the open revision's id.

Two related shapes: `ignored_fields` in a 202 lists what was dropped (`status`
always is — the gate exists precisely so a write can't publish itself), and a
request that changes nothing returns 200 with `{"status": "unchanged"}`.

Drafts are unaffected: writes to an unpublished record apply immediately.

## Running as a scheduled agent

Everything above assumes a person asked you to do something. The CMS can also
hand you work on its own: someone defines an **agent** in the UI (instructions,
which part of the site it works, a cadence) and the CMS queues a **run**. It
never executes one — that's what this machine is for.

This needs the **Agents** plugin switched on in the CMS (Settings › Plugins).
While it's off, `/api/agent_runs` answers 404 and `cms work` has nothing to
claim — `cms manifest` lists the plugins that are on.

The loop is:

```sh
cms work                  # claim the next queued run; prints its brief
                          # exit 3 = nothing queued. That is normal, not an error.
cms run-start <id>        # you have the lease now
cms run-step <id> "read 40 pages, 6 titles over length"
cms run-ping <id>         # every few minutes on a long run
cms run-done <id> "Rewrote 6 titles; filed 2 findings"
```

The brief is the whole job: `agent.instructions` is what to do, `scope` is what
to do it to, `capabilities` lists the commands you may use, and `rules` are
non-negotiable. It's a snapshot taken when the run was queued, so it doesn't
change under you — work from the brief you were handed, not from re-reading the
agent.

Three things matter more than the rest:

- **`cms run-ping` is not just a keepalive.** It answers whether to carry on.
  If it comes back `"continue": false`, the run was canceled or handed to
  another worker while you were busy — stop immediately. Anything you do after
  that point is work nobody asked for, on a run someone else may be redoing.
- **Finish the run, whatever happened.** `cms run-done` on success,
  `cms run-fail <id> "<what went wrong>"` on failure. A run you abandon sits
  claimed until its lease lapses and then gets handed to someone else, who
  repeats everything you already did.
- **File what you couldn't fix.** Most SEO work isn't an edit: a topic with
  demand and no page, two pages competing for one query, a claim that needs a
  human to confirm. Those go to the review queue as findings, not into your
  summary where nobody reads them:

```sh
cms recommend content_gap "No page for 'pricing for teams'" \
  --body "Nothing covers it; the pricing page links to a /teams that 404s." \
  --impact 4
cms recommend metadata "Title is 94 characters" --subject page:/about/team
cms findings                 # what's already filed — don't duplicate
```

Kinds: `content_gap` `metadata` `schema` `internal_linking` `cannibalization`
`technical` `freshness` `accessibility`. Export `CMS_AGENT_RUN_ID=<id>` and
findings are attributed to the run automatically.

Filing a finding is not the same as making the change. Accepting one records a
decision; the change still goes through the ordinary write path and the review
gate above.

## Service tokens

A service token is a credential for a machine — the published site, a build
pipeline, an agent — rather than for a person. It belongs to the workspace and
carries the role named on it, so nothing that happens to a human account takes
production down.

```sh
cms service-tokens                          # every token, and the roles available
cms service-token create --name PRODUCTION --role "Production site"
cms service-token reveal 3                  # show the secret again
cms service-token rotate 3                  # new secret; the old one dies at once
cms service-token revoke 3
```

The published Astro site holds a **read-only** token on the **Production site**
role, stored in its environment as `PRODUCTION_TOKEN`. That is not the token you
are using: agents run on `USER_AGENT_TOKEN`, which sits on the **Agent** role and
can write but not publish. Don't reach for one when the task calls for the other.

Only `create`, `reveal` and `rotate` return a secret, and only once each. Print
it for the person who asked; never write one into this file, into the site repo,
or into a commit. Issuing one needs `settings:write`, the same capability the
admin UI asks for.

## Credentials

Credentials live in `~/.config/cms/<profile>.env` (mode 600) as `CMS_URL` and
`USER_AGENT_TOKEN`, or in the environment if you'd rather pass them
per-command. The token authenticates you as a **user**, with exactly that
user's role — the same permissions they have in the web UI.

One machine can hold several identities — a person and a service account, or
two sites. `cms profiles` lists them; `--profile <name>` or `CMS_PROFILE`
picks one. With a single profile configured, it is used automatically.

Never write the token into this file, into the site repo, or into a commit. If
it leaks, or a call comes back `401`, reconnect in a browser — nothing is
pasted anywhere:

```sh
cms login --url __CMS_URL__
```

## Rules

- **A 403 means the role doesn't grant it**, not that the API is broken. Say so
  and stop; don't hunt for a way around it. If the work is finished but you
  can't publish it, open a review request — `cms review request Page pricing
  "ready for a look"` — so it's waiting on a human rather than lost.
- **Draft first.** Create pages and entries with `"status":"draft"` unless the
  user asked for them published — publishing is visible to the world and
  triggers a site rebuild.
- **The CMS is the source of truth for content**, the repo is the source of
  truth for templates and layout. Don't hard-code copy into the Astro repo that
  belongs in a collection, and don't reshape a collection to work around a
  template you could change instead.
- **Verify before you call it done.** For site changes that means the repo's own
  checks (`npm run build` at minimum) and a PR — not just a green diff. For
  content changes, re-read what you wrote (`cms page <path>`) and confirm it
  looks the way you intended. If you triggered a deploy, `cms deploy` tells you
  whether it actually succeeded — check, don't assume.
- **A slug change orphans inbound links.** Add the redirect in the same breath:
  `cms redirect add /old-path /new-path 301`.
- Report what you actually did: what you changed in the CMS, what you changed in
  the repo, and anything you couldn't verify.

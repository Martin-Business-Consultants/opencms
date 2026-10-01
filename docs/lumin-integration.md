# Lumin integration

This CMS is one half of a pair. The other is **Lumin** (`../ads`), the growth
side: paid campaigns, Search Console, cross-channel analysis and the agents that
act on it. Two deployables, no shared database — bound by a site key and two
HTTP crossings.

**The contract, in full, with examples:** [`../ads/docs/cms-contract.md`](../../ads/docs/cms-contract.md).
Its machine-readable form is `spec/fixtures/contracts/cms_contract.json`, which
is **mirrored byte-for-byte** in the Lumin repo. Both suites assert against it
and against each other's copy. Edit both, or neither.

Why it is pinned this hard: the seam had already broken in both directions and
neither suite noticed for a month. See `../ads/docs/ecosystem-audit.md` §1.

## What crosses

| Direction | How | Owned by |
|---|---|---|
| Content changes → Lumin | `Webhook` on `page.*` / `entry.*` | this app emits |
| Findings → this app | `POST /api/recommendations` | this app receives |
| Page/redirect/sitemap reads → Lumin | the scoped `/api/*` surface | this app serves |

`Site.key` here (`SITE_KEY`, else the first label of the install's
`APP_HOST`) **equals** `Site#cms_key` in Lumin. It is the only identifier that
crosses, and it is what every payload sends as `tenant` — the field keeps that
name so Lumin didn't have to change. A Lumin tenant is an *agency* holding many
sites, so one Lumin tenant maps to several CMS installs, one per site. When an
install moves to a new host, set `SITE_KEY` to keep the key Lumin knows.

## Two things that are easy to get wrong

**The webhook secret is not ours to generate.** For Lumin to verify the
`X-CMS-Signature` HMAC, the `Webhook` row pointed at Lumin must be created
carrying **Lumin's `Site#webhook_secret`** — not the one `Webhook` generates for
itself. Set it explicitly:

```ruby
Webhook.create!(name: "lumin", url: "https://<agency>.golumin.io/webhooks/content",
                events: Webhook::EVENTS.grep(/\A(page|entry)\./),
                secret: "<the Lumin Site's webhook_secret>")
```

This is the one value the two sides must agree on, and it belongs in
provisioning rather than in whoever wires the webhook up by hand.

**`webhook_payload[:url]` is load-bearing.** Lumin joins Search Console rows to
records here *by URL*. A payload whose URL differs from the address the site
actually publishes describes a record Lumin can never match. That is why
`PubliclyAddressable` is shared by the webhook payloads and `Sitemap` — so the
two cannot drift. If you add a content type that Lumin should see, give it
`default_public_path` and include the concern; don't recompute the address.

`site_base_url` (Settings › General) is what makes the URL absolute. Without it
the payload carries a relative path, which is honest but unjoinable — treat an
empty `site_base_url` as an incomplete setup.

## Running the contract tests

```bash
bundle exec rspec spec/contracts/lumin_contract_spec.rb
```

The mirror check skips when `../ads` isn't checked out beside this repo, so CI
that builds one repo alone still passes; check both out to get the real pin.

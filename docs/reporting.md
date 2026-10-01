# Marketing & reporting

Local-SEO reporting for the business a site publishes: what search engines,
the Google map pack and the AI assistants can see about it. Data comes from
[DataForSEO v3](https://docs.dataforseo.com/v3/); the CMS stores snapshots.

**Sidebar → Reporting → Reports.** Credentials and the business being reported
on live at **Settings → Reporting**.

## The Marketer's Report — the front page

The sidebar group is **Marketing**; its front page is `/marketing`, the
Marketer's Report. Everything on it is built in two layers, kept apart on
purpose:

- **Deterministic** — `Marketing::Scorecard` (five pillar scores, 0–100,
  each metric's progress toward its target from the latest snapshots) and
  `Marketing::Actions` ("Do next": rules over agent findings, citation gaps,
  unanswered reviews, listing problems, site issues, never-run or stale
  reports, and template-recommended agents that aren't on). Every item names
  an **owner** — `you` (the marketer), `owner` (the business owner), or
  `agent` (with the template that does that kind of work, for one-click
  hand-off) — and cites its evidence.
- **Narrative** — `Marketing::Narrative` asks the model (via `Ai::Oneshot`) for
  3–5 sentences *about* the computed facts, cached against a digest of them.
  It never sees a report's raw data and never produces a number. Absent, not
  wrong, when no AI key is configured.

`/marketing/client` is the same data for the business owner: their actions,
what we're working on, the scores in plain words — no costs, agents or ids.
Printable. `POST /marketing/baseline` queues the template's recommended
reports through `Report.queue` (`Marketing::Overview#run_baseline`); `POST /marketing/hand_off` (`Marketing.hand_off`) installs an
agent from its template if needed (disabled) and queues one run.

## Business templates and guided setup

`config/businesses/*.yml`, one per business type, versioned like agent
templates and validated by `Marketing::BusinessRegistry` (file name is the
key; reports, agents and targets must exist). A template declares the GBP
category, schema type, storefront vs service-area (which sets the Rank map
grid: 5×5 at 1.5 km vs 7×7 at 3 km), services, keyword patterns
(`{service} {city}`, `{modifier} {service} {city}`…), vertical directories,
recommended reports with cadences, recommended agents, target defaults, and
an optional content scaffold.

`/marketing/setup` is the guided flow: pick a type, confirm the business,
review what the template derived for the city (keywords, directories, map,
targets — all editable), then choose whether to scaffold draft pages, turn on
the weekly refresh, and run the baseline. `Marketing::Setup` writes the same
`Setting["reporting"]` the settings page edits plus `Setting["marketing"]`
(type, targets); it is a faster way in, not a second place things live.

**Nothing turns itself on.** Agents install disabled; the weekly refresh is a
switch the person flips; the baseline shows its cost before the button.

## Who sees this

Reports, the Marketer's Report and the agents are the **administrator's**.
The two canned human roles installed on every site — **Editor** (writes and
publishes content) and **Author** (writes for an editor to publish) — hold no
`reports:*`, `agents:*` or `recommendations:*` capability, so the Marketing
and Automation groups don't appear in their sidebar, the findings column is
absent from their Approvals queue, and the API refuses their token for
`/api/reports`. They keep everything about content, including the review
queue (Approvals is gated on `pages:read`, and shows findings only to a role
that may see them).

Widening this is a deliberate act on the **Roles** page: grant `reports:read`
to let a role watch the report, `reports:run` to let it spend, `agents:*` to
let it manage agents. The machine **Agent** role keeps `reports:read`,
`agents:run` and `recommendations:write` — it reads reports and files findings
— and never `reports:run`.

`MakeReportsAndAgentsAdminOnly` (2026-09-18) applied this to existing sites:
it strips those capabilities from roles *named* Editor and Author, leaves
custom roles alone, and creates the two roles where an older site lacked
them.

## Why snapshots, not a live proxy

Three reasons, and the third is the important one:

- The calls are slow. `llm_mentions/target_metrics` is documented at up to 120
  seconds, and Local rankings makes one SERP call per tracked keyword.
- They cost money per call, so a page refresh must not be a purchase.
- **The value is in the comparison.** "Are we in the map pack" matters much
  less than "we were, in March". A cache gives you the first two and throws
  the third away.

So `Reports::RunsController#create` calls `Report.queue`, which creates a
`Report` row in `queued` and dispatches `Report::RunJob` (`Report#run_later`),
and redirects. The page polls while anything is in flight.

`Report#data` holds the *normalized* result, not the raw response — the raw
envelopes run to hundreds of KB of mostly irrelevant JSON. `Report#params`
denormalizes the `Reports::Profile` as it was at run time, so a later settings
change can't silently relabel history.

## The pieces

All under `engines/local_marketing/` (the Local Marketing plugin), and all in
`app/models`: the plugin has no services (STYLE.md).

| Thing | Where | Job |
|---|---|---|
| `DataForSeo::Client` | `app/models/data_for_seo/` | HTTP, auth, error handling (a plain object at the plugin's edge to a paid API) |
| `Reports::Profile` | `app/models/reports/profile.rb` | the business being reported on; `.change` saves Settings › Reporting |
| `Reports::Definition` | `app/models/reports/definition.rb` | base class for one report |
| `Reports::Catalog` | `app/models/reports/catalog.rb` | the registry |
| `Report` | `app/models/report.rb`, `app/models/report/` | one stored run: `Runnable` (`queue`, `run_later`, `run_now`), `Historical` (`previous`, `stale?`), `Trended` (`metrics`), `Priced` (`spend`) |
| `Report::RunJob` | `app/jobs/report/run_job.rb` | calls `run_now` in the background |
| `Reports::Dismissals`, `Reports::CitationStatuses` | `app/models/reports/` | what a person decided, kept in settings across runs |
| `Reports::ConnectionTest` | `app/models/reports/connection_test.rb` | Settings › Reporting › Test |

## The catalog

Twenty reports in six groups. Within a group, the one to run first is first.

| Key | Group | DataForSEO endpoint(s) | Needs | ~Cost |
|---|---|---|---|---|
| `llm_visibility` | AI visibility | `ai_optimization/llm_mentions/target_metrics/live` | brand terms | $0.02 |
| `ai_answers` | AI visibility | `ai_optimization/{chat_gpt,gemini}/llm_responses/live` | keywords + brand terms | $0.15 |
| `ai_keyword_demand` | AI visibility | `ai_optimization/ai_keyword_data/keywords_search_volume/live` | tracked keywords | $0.01 |
| `ranked_keywords` | Search | `dataforseo_labs/google/ranked_keywords/live` | domain | $0.02 |
| `visibility_history` | Search | `dataforseo_labs/google/historical_rank_overview/live` | domain | $0.02 |
| `keyword_demand` | Search | `keywords_data/google_ads/search_volume/live` | tracked keywords | $0.05 |
| `keyword_opportunities` | Search | `dataforseo_labs/google/keyword_ideas/live` | tracked keywords | $0.03 |
| `competitors` | Search | `dataforseo_labs/google/competitors_domain/live` | domain | $0.02 |
| `search_trends` | Search | `keywords_data/google_trends/explore/live` | tracked keywords | $0.01 |
| `local_rankings` | Local | `serp/google/organic/live/advanced` | keywords + domain | $0.05 |
| `maps_rankings` | Local | `serp/google/maps/live/advanced` | keywords + business name | $0.05 |
| `rank_map` | Local | `serp/google/maps/live/advanced` × (grid² × keywords), from coordinates | business name + map keywords | $0.15 |
| `citations` | Local | `serp/google/organic/live/advanced` (`site:` per directory) → `on_page/content_parsing/live` | business name | $0.03 |
| `business_profile` | Local | `business_data/google/my_business_info/live` | business name | $0.02 |
| `local_competitors` | Local | `serp/google/maps/live/advanced` → `business_data/business_listings/search/live` | business name | $0.02 |
| `google_reviews` | Reputation | `business_data/google/reviews/task_post` → `task_get` **(task-based)** | business name | $0.01 |
| `web_mentions` | Reputation | `content_analysis/summary/live` | brand terms | $0.02 |
| `backlinks` | Authority | `backlinks/{summary,referring_domains,anchors,timeseries_summary,timeseries_new_lost_summary}/live` | domain | $0.10 |
| `site_audit` | Site health | `on_page/instant_pages` (rendered, with our probe) + plain GETs | audit URLs | $0.05 |
| `page_health` | Site health | `on_page/instant_pages` | audit URLs | $0.03 |
| `lighthouse` | Site health | `on_page/lighthouse/live/json` | audit URLs | $0.04 |

Two of these depend on another report's output, best-effort: **Keyword
opportunities** marks the ideas already in the latest **Ranked keywords**
snapshot (without one, nothing is marked and the page says so), and **Local
competitors** first finds the business on Maps to get its coordinates and
category — the Business Listings index has no notion of a city, only a
radius around a point.

**Backlinks' two timeseries calls send no `date_from`.** The docs give
`yyyy-mm-dd` with a 2019 minimum; the live API answered
`40501 Invalid Field: 'date_from'`. The default window (through today) is
requested instead and trimmed to 13 months in code. Both history calls are
also non-fatal — the summary, domains and anchors have already been paid for,
and a chart is not worth failing them over; `history_note` says what happened.

**Rank map is the geo-grid.** The Maps SERP endpoint takes a
`location_coordinate` (`lat,lng,14z`), so the same keyword is asked from an
n×n grid of points `spacing` km apart around the business — its coordinates
come from one Maps search for the name — and the business's `rank_group` is
recorded at each. Row 0 is north, column 0 west. The page draws it on a
Leaflet map (OpenStreetMap tiles, attribution required, inverted in dark
mode); the table twin is the grid as rows. "Share of local voice" — the share
of cells with us in the top 3 — is the trend metric. Grid size (3/5/7),
spacing and the map's own keyword list are in Settings → Reporting, because
every cell is a paid call per keyword.

**Google reviews is the one task-based report.** DataForSEO can't serve
reviews live, so `Definition#await_task` posts a task and polls `task_get`
with a slow backoff (up to four minutes). Status `20100` on post means
*created*, and `40601`/`40602` on get mean *not yet* — neither is an error, and
`DataForSeo::Client#post_task` / `#task_get` say so. The post is where the
charge happens, so a timeout is money spent for nothing; the message says so.

Costs are the estimate on the run button; `Report#cost` is what was actually
charged, which is the number worth trusting — the published price is a list
price and varies with the parameters sent.

## Adding a report

Five steps, and the shape is deliberately the same as `RecurringTasks`:

1. Write `engines/local_marketing/app/models/reports/definitions/<key>.rb`, subclassing
   `Reports::Definition`. Implement `call` and return a **flat, small** Hash —
   the handful of numbers that answer the question, not the payload. Declare
   `location_granularity` (and `locations_api` if it's `:country`, merging
   `locale_data` into the result) — see below, this is the easiest thing to
   get wrong.
2. Register the class in `Reports::Catalog::DEFINITIONS`.
3. Declare `trend_metrics` (the handful of figures worth plotting across
   snapshots, each with `key`, `label` and whether `up` or `down` is good) and
   implement `trend_point(data)` to pull them out of a stored result.
4. Nothing else, usually: the report page renders any result as text —
   named figures, each list of rows as a table, each nested part as its own
   section (`reports/_data.html.erb`). A report that needs its own view (a
   form per row, like Citations) adds a partial under
   `engines/local_marketing/app/views/reports/kinds/` and registers it.

No migration — `data` is JSON, and the model knows nothing about DataForSEO.

## Location — the thing that bites

Three endpoints in a row rejected `location_name` with

```
40501 Invalid Field: 'location_name'
```

despite each one's documentation listing the field. Whatever the cause (a
value that doesn't match the API's spelling to the character — `"Cardiff, Wales"`
with spaces is not `"Cardiff,Wales"`; a live method stricter than its docs), the
fix is structural: **never send a name.** `DataForSeo::Locations` looks the
location up in the endpoint's *own* list and sends the code.

"Location" is also not one thing across DataForSEO:

| Granularity | Endpoints | Reports | Resolved against |
|---|---|---|---|
| **city** | SERP, Business Data | Local rankings, Business profile | `serp/google/locations/{iso}`, `business_data/google/locations/{iso}` |
| **country** | Labs (90), LLM Mentions (92), AI Keyword Data (94) | Ranked keywords, AI visibility, AI keyword demand | each API's `locations_and_languages` |
| **none** | On-Page | Page health | — |

Every definition declares `location_granularity` and, unless it's `:none`, a
`locations_api` naming which list to resolve against. `Definition#locale_params`
then always yields `{location_code:, language_code:}`; a new report has to
*decide* rather than inherit whichever default suited the last one.

The city lists are ~100k rows in total, so they are fetched **per country** —
a few thousand rows, free, cached a week — keyed by the `country_iso_code`
read off the country list. City matching is full-name-to-the-character first
(after normalising the spaces people type), then by the first segment among
rows whose `location_type` is City, so `"Cardiff"` finds
`"Cardiff,Wales,United Kingdom"`. An explicitly-set `location_code` is
trusted as-is.

Fallback behaviour differs by scope, on purpose:

- A **country** report that can't resolve runs against the United States and
  says so — country-level AI figures for the wrong country are still
  indicative. `Resolved#reason` (`no_country` / `unsupported` /
  `lookup_failed`) drives the banner, so it names the true cause.
- A **city** report that can't resolve **fails, with the fix in the message**.
  A national SERP has no map pack for a business in Cardiff; running it would
  produce a confident answer about the wrong place, and spend money doing it.

Two traps worth restating: `Profile#location_code` defaults to 2840, and that
default must never reach resolution (use `configured_location_code`, nil when
unset); and **Settings → Reporting → Test connection** resolves both the
country and the city and says what each report will use — check there before
paying for a run.

## The pages

Reporting pages are plain text for now — no charts. Every page says what was measured, when, and what it cost:

- **The index** lists each group's reports with what each one answers, when
  it last ran, its headline figures with the change since the run before,
  and what it's missing; runs in progress are listed above. A window quick
  filter (`?range=30d`, presets 7d · 30d · 90d · 1y · all, parsed by
  `Reports::DateRange`) picks which snapshots count.
- **A report page** shows the headline figures (`trend_metrics`) against the
  run before, any warnings from the run, the stored result as text
  (`reports/_data.html.erb`), and the snapshots in the window. It refreshes
  itself while a run is queued or running.
- **Page-only state** a report needs (Citations' per-directory statuses)
  still comes from `Definition.page_props`, which the show controller hands
  to the view as `@extra`.

## The docs are not the API — and what the code does about it

Six times, an endpoint has refused a field its own documentation lists, always
with `40501 Invalid Field: '<name>'`:

| Endpoint | Refused | What the code does now |
|---|---|---|
| `llm_mentions`, `dataforseo_labs`, `business_data` live | `location_name` | resolves every location to a code (see above) |
| `backlinks/timeseries_*` | `date_from` | asks for the default window, trims in code |
| `gemini/llm_responses/live` | `web_search_country_iso_code`, `web_search_city` | per-platform `geo:` flag; Gemini is told the location in the system message |
| `google_trends/explore/live` | `item_types` | graph live; map and queries as awaited tasks, one item type each |

So `Definition#fetch` now absorbs the class: on a `40501` that names a field the
task actually sent, and that isn't required (`keyword`, `target`, `url`,
`user_prompt`, `model_name`, the location/language codes…), it drops that one
field and retries — at most three drops — and records the fact in
`Definition#warnings`. `Report#run_now` stores warnings on the snapshot as
`data.warnings`, and the report page lists them once under "Notes from this
run". A refinement the API won't take costs a note, not a failed report.

Secondary calls that aren't the report's main question (Backlinks history,
Trends map and queries) are non-fatal on the same principle and write to the
same `warnings`.

## Citations — the audit and the checklist

No API audits citations, so `Citations` is built from two that exist: one
Google search scoped to each directory (`site:yelp.com "Acme Storage" Austin`)
finds the listing, and one content-parsing call reads it and checks the name,
phone (digits, last ten) and address (street number + ZIP) against the NAP.
The NAP comes from Settings → Reporting when set, otherwise from the latest
Business profile snapshot — Google's version, which is what the others are
compared to anyway. Apple Maps and Bing Places don't expose listings to
Google; they're listed as *manual* with the reason, never as *missing*.

What a person has **done** about each directory — to do · submitted · live ·
needs fix · ignored, with a note — is the management half, and it lives in
`Setting["citations"]` (via `CitationStatusesController`), not on the snapshot,
because it changes without a paid run. `Definition.page_props` is how a report
hands such page-only state to its renderer; the show controller merges it in
as `extra`.

## Agents on the reports

`config/agents/reporting_analyst.yml` is a weekly agent (Monday 07:00) that
reads the snapshots and files findings — never runs a report. It uses the
`read_reports` capability (`cms reports`, `cms report <kind> [--previous]`,
backed by the read-only `Api::ReportsController`; in-process runs get
`ListReports`/`GetReport` tools). `reports:run` is deliberately not an agent
capability: spending is a person's decision.

**It is off until a person turns it on.** Like every template, it appears
under Agents → templates after `seed_templates`, installs as a disabled row,
and runs only once someone sets its scope and enables it. Nothing in this
repo enables an agent on its own.

## Three things that are easy to get wrong

**DataForSEO answers 200 to most failures.** The real outcome is in
`status_code`, at *two* levels: once for the request, once per task. 20000
means OK in both places. A client that only checks `Net::HTTPSuccess` reports
an exhausted balance, a bad credential and an empty result as the same silent
success. `DataForSeo::Client` raises on all three — don't route around it.

**The body is always an array**, even for one task. `Client#post` wraps for
you; `#post_many` batches and returns `nil` in place for a task that failed
individually, so the caller keeps the correspondence with what it sent.

**`reports:run` spends money.** It is deliberately separate from
`reports:read` and sits with the roles that can already publish. The agent
role gets read only — an agent that could trigger its own paid reports on a
loop is a bill, not a feature. Both the controller and the recurring recipe
guard against a second in-flight run of the same kind, because an impatient
double-click is otherwise two charges for one answer.

## Scheduling

`RecurringTasks::Recipes::ReportRefresh` re-runs selected reports so the
history builds itself — a snapshot nobody takes regularly is just a spot
check. It ships **disabled**, defaults to the two cheapest reports, and is
configured at **Tools → Schedules**. Turning it on is spending money on a
timer; that should be a deliberate act.

## Testing

```bash
bundle exec rspec spec/models/data_for_seo spec/models/reports spec/models/report spec/requests/reports_spec.rb
```

No live calls. `spec/models/reports/definitions_spec.rb` feeds each
definition a response shaped like the documented one and asserts on the
reduction — that is where the bugs are, not in the HTTP.

Sandbox mode (Settings → Reporting) routes to `sandbox.dataforseo.com`: free,
and the data is fake. It checks the wiring, not the business.


## Site audit

The one report that compares the live site with what the CMS *expects*,
rather than asking a crawler what it thinks. The CMS knows which tags should
load and how consent gates them (Scripts, Consent), which forms exist and
where they post (Forms), the business phone (Reporting) and the site URL
(General) — so `Reports::Definitions::SiteAudit` renders the pages in a real
browser via DataForSEO `instant_pages` (`enable_javascript`, `load_resources`,
our `custom_js` probe in `Reports::Audit::Probe`) and compares.

The home page is rendered twice: plain, and with a Google Ads click
(`gclid`) in the URL — the visit dynamic number insertion swaps the number
for. Four analyzers (`Reports::Audit::{Tracking,Phones,Forms,Search}`) turn
the evidence into **findings** (key, area, severity, title, body, fix) and
**passes**:

| Area | What it catches |
|---|---|
| consent / tracking | banner on in CMS but embed missing on the site; tags and cookies running before consent (opt-in); tags on the site not managed in Scripts; **every CMS script's on-site verdict** (the probe reads the embed's script list and tells the runtime to accept, then records what it injected — `on_site`, `hardcoded`, `not_served`, `not_injected`, `category_off`, `embed_missing`, `banner_off`); no policy link |
| calls | no phone on the home page; not tap-to-call; number ≠ business number (no call tracking); call tracking installed but never swaps; tel: link dials a different number |
| forms | form not on any audited page; required field missing from the rendered form; posts outside the CMS; no spam trap; nobody notified; definition rejects a valid submission; never received a submission; stray non-CMS forms; base URL unset (open CORS) |
| search | home not 200; robots.txt missing / blocks all; sitemap missing / empty / wrong host / unannounced; no verification tag; noindex; canonical to another host; no viewport; www/non-www both live; no LocalBusiness schema |

The audit never submits a live form — it validates a synthetic submission
against the definition (the code the real endpoint runs) instead. A Search
Console *connection* needs a Google login the CMS doesn't hold; the audit
checks the site is verifiable and says so.

**Where it shows.** Tools → Scripts carries an "On the site" column from the latest audit and a "Check the site" button. The dashboard card (`Reports::Audit::Dashboard`) lists the
open findings with their fix links; critical and high findings become "do
next" actions on the Marketer's Report; the `site` pillar counts critical
findings. A person can **dismiss** a finding ("verified via DNS") — kept in
`Setting["site_audit"]` by finding key (`Reports::Dismissals`) so it holds
across weekly runs, and restorable. The optional narrative is written by the
cheap tier (DeepSeek V4 Flash) about the findings it is handed, never adding
one.

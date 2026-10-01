# Open Knowledge Format (OKF) in the CMS

> Google's [OKF](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing/) is a vendor-neutral spec for agent-readable knowledge: markdown files with YAML frontmatter, standard fields (`type`, `title`, `description`, `resource`, `tags`, `timestamp`), shipped as plain directories.

## The Core Insight

**The CMS is already an OKF engine.**

A `CollectionEntry` *is* an OKF document:

| OKF Field | CMS Equivalent |
|-----------|---------------|
| `title` | `collection_entry.title` |
| `description` | `collection_entry.frontmatter["excerpt"]` or derived from body |
| `type` | `collection.slug` |
| `tags` | `collection_entry.tags` |
| `timestamp` | `collection_entry.published_at` or `updated_at` |
| `resource` | `content_references` (linked assets, pages, entries) |
| Markdown body | `collection_entry.body_markdown` |
| YAML frontmatter | `collection_entry.frontmatter` (JSON column, schema-validated) |

The CMS already validates frontmatter against JSON schemas per collection, versions every change, and maintains content references. OKF is not a foreign format — it's a serialization of what the CMS already does.

---

## 5 Ways OKF Fits

### 1. OKF Export — CMS Content as Agent Knowledge

**Problem:** External agents (Runwell assistant, Claude Code, custom scripts) currently have to scrape HTML or call a JSON API to consume CMS content. Both are brittle.

**Solution:** Export any collection (or the whole site) as an OKF directory tarball.

```
okf-export/
├── okf.manifest.json          # Bundle metadata
├── posts/
│   ├── 2026-06-year-in-review.md
│   ├── 2026-05-rebrand-announcement.md
│   └── _index.md              # Collection-level metadata
├── case_studies/
│   ├── acme-rebrand.md
│   └── betacorp-launch.md
└── pages/
    ├── home.md
    ├── services.md
    └── about.md
```

Each `.md` file:

```markdown
---
type: case_studies
title: "ACME Rebrand"
description: "How we repositioned ACME from budget to premium"
resource:
  - kind: asset
    ref: cover-image-acme.jpg
  - kind: page
    ref: services/branding
tags:
  - branding
  - b2b
  - manufacturing
timestamp: "2026-06-10T09:00:00Z"
---

## The Challenge

ACME's brand was stuck in the 1990s...
```

**Use cases:**
- **Runwell AI** downloads the latest `case_studies/` OKF bundle to ground its responses in actual agency work
- **Claude Code / Agent SDK** mounts the CMS export as an `AGENTS.md`-style knowledge wiki for a project
- **External data teams** consume CMS content without API integration
- **Backup / migration** — full site state as a git-trackable directory

**Implementation:**

```ruby
# app/models/okf/exporter.rb
module Okf
  class Exporter
    OKF_VERSION = "0.1"

    def initialize(site:, collections: nil, status: "published")
      @site = site
      @collections = collections || Collection.pluck(:slug)
      @status = status
    end

    def to_tarball(io)
      Gem::Package::TarWriter.new(io) do |tar|
        tar.add_file("okf.manifest.json", 0644) do |f|
          f.write(manifest.to_json)
        end

        entries.find_each do |entry|
          path = "#{entry.collection.slug}/#{entry.slug}.md"
          tar.add_file(path, 0644) do |f|
            f.write(to_okf_document(entry))
          end
        end
      end
    end

    private
      def entries
        CollectionEntry
          .joins(:collection)
          .where(collections: { slug: @collections })
          .where(status: @status)
      end

      def manifest
        {
          okf_version: OKF_VERSION,
          site: @site,
          exported_at: Time.current.iso8601,
          collections: @collections,
          entry_count: entries.count
        }
      end

      def to_okf_document(entry)
        frontmatter = {
          "type" => entry.collection.slug,
          "title" => entry.title,
          "description" => entry.frontmatter["excerpt"] || entry.search_text.truncate(200),
          "resource" => resources_for(entry),
          "tags" => entry.tags.map(&:title),
          "timestamp" => (entry.published_at || entry.updated_at).iso8601
        }.compact

        "#{frontmatter.to_yaml}---\n\n#{entry.body_markdown}"
      end

      def resources_for(entry)
        entry.content_references.map do |ref|
          { "kind" => ref.kind, "ref" => ref.ref_id }
        end
      end
  end
end
```

**API endpoint:**

```ruby
# app/controllers/api/v1/okf_exports_controller.rb
class Api::V1::OkfExportsController < Api::V1::BaseController
  def show
    exporter = Okf::Exporter.new(
      site: Site.key,
      collections: params[:collections]&.split(","),
      status: params[:status] || "published"
    )

    send_data exporter.to_tarball(StringIO.new).string,
              filename: "#{Site.key}-okf.tar.gz",
              type: "application/gzip"
  end
end
```

---

### 2. OKF Import — Ingest External Knowledge

**Problem:** Client research, internal runbooks, competitive analysis, and data-team documentation live in scattered places (Notion, Google Docs, git repos).

**Solution:** Import any OKF-compliant directory as a CMS collection.

**Use cases:**
- A data team's `docs/` directory (OKF-formatted) imports as a `knowledge_base` collection
- Client onboarding documents imported as a private `client_docs` collection
- Research notes from an Obsidian vault synced into the CMS for publishing

**Implementation:**

```ruby
# app/models/okf/importer.rb
module Okf
  class Importer
    def initialize(collection_slug:, tarball_io:)
      @collection = Collection.find_by!(slug: collection_slug)
      @tarball = Gem::Package::TarReader.new(Zlib::GzipReader.new(tarball_io))
    end

    def import!
      @tarball.each do |entry|
        next unless entry.file? && entry.full_name.end_with?(".md")
        next if entry.full_name.include?("_index.md")

        content = entry.read
        frontmatter, body = parse_okf(content)

        CollectionEntry.create!(
          collection: @collection,
          slug: slug_from_filename(entry.full_name),
          title: frontmatter["title"] || "Untitled",
          body_markdown: body,
          frontmatter: frontmatter.slice(*@collection.fields.map { |f| f["name"] }),
          status: "draft"
        )
      end
    end

    private
      def parse_okf(content)
        if content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m
          [YAML.safe_load($1), $2.strip]
        else
          [{}, content]
        end
      end

      def slug_from_filename(path)
        File.basename(path, ".md")
      end
  end
end
```

---

### 3. Internal Knowledge Collections

**Problem:** The CMS is currently positioned as a *public* content tool (pages, blog, case studies). But agencies also need *internal* knowledge: process docs, runbooks, brand guidelines, research, meeting notes.

**Solution:** Use the CMS for both. Create internal-facing collections that are OKF-native:

| Collection | Purpose | Frontmatter |
|------------|---------|-------------|
| `process` | How we work | `owner`, `last_reviewed`, `status` |
| `research` | Competitive/market research | `topic`, `source`, `confidence` |
| `runbooks` | Incident / deployment procedures | `severity`, `owner`, `last_tested` |
| `decisions` | ADRs and strategy decisions | `deciders`, `status`, `date` |
| `meetings` | Meeting notes | `attendees`, `date`, `action_items` |

All of these are just `CollectionEntry` records with markdown bodies. The difference is:
- **Not routed** through the public site frontend
- **Access-controlled** via permissions
- **Exported as OKF** for agents to consume as organizational memory

**The CMS becomes the agency's single source of truth for *all* knowledge — public and private.**

---

### 4. Agent-Native Context Generation

**Problem:** When the CMS AI (`Ai::ProposalGenerator`) or Runwell AI needs context about existing content, it currently queries the database or reads JSON API responses.

**Solution:** Generate on-the-fly OKF bundles for agent context. Instead of sending structured JSON, send a markdown document — the format agents read best.

**Example — CMS AI writing a new blog post:**

```ruby
# In Ai::ProposalGenerator, before generating:
context = Okf::ContextBuilder.new(
  collections: ["posts", "case_studies"],
  limit: 5,
  recency: 3.months
).to_okf

# context is a single markdown string:
# ---
# type: context_brief
# title: "Recent agency content"
# ---
#
# ## posts/2026-05-rebrand-announcement
# [excerpt...]
#
# ## case_studies/acme-rebrand
# [excerpt...]
```

This context string is injected into the AI prompt. The agent receives knowledge in the same format it would read from an Obsidian vault or LLM wiki — no translation layer needed.

**Example — Runwell AI answering "What's our positioning on X?":**

```ruby
# AI::Tools::FetchCmsKnowledge
# Instead of JSON API:
def execute(query:)
  # Search FTS, build OKF context brief
  entries = CollectionEntry.search(query).limit(10)
  Okf::ContextBuilder.from_entries(entries).to_okf
end
```

The Runwell assistant receives markdown + frontmatter, not JSON. It can reason about it naturally.

---

### 5. Content-as-Code / Obsidian Sync

**Problem:** Writers and strategists often prefer local tools (Obsidian, VS Code, git) for drafting. The CMS web editor is great for structured content but friction-heavy for exploration.

**Solution:** Bidirectional OKF sync.

**Git-based workflow:**
1. Writer clones `mbc-content` git repo
2. Repo contains OKF directories mirroring CMS collections
3. Writer edits `.md` files locally in Obsidian
4. Push triggers CI → CMS import API
5. CMS publishes, triggers webhooks, updates search index

**CMS → Git (export):**
```bash
# Cron or webhook-triggered
curl -H "Authorization: Bearer $PRODUCTION_TOKEN" \
  https://cms.mbc.com/api/v1/okf/exports?collections=posts,case_studies \
  | tar -xzf - -C content/
git add . && git commit -m "sync from cms" && git push
```

**Git → CMS (import):**
```bash
# On PR merge
cd content/
tar -czf - . | curl -X POST \
  -H "Authorization: Bearer $PRODUCTION_TOKEN" \
  -H "Content-Type: application/gzip" \
  --data-binary @- \
  https://cms.mbc.com/api/v1/okf/imports?collection=posts
```

**Benefits:**
- Writers use Obsidian / VS Code / git for drafting
- CMS handles publishing, SEO, scheduling, permissions
- Full version history in git + CMS versions
- Agents can mount the git repo directly as knowledge

---

## Architecture Decision: Native OKF vs. Adapter Layer

Two approaches:

### A. Native OKF (recommended)

Treat OKF as the canonical format. `CollectionEntry` stores `body_markdown` + `frontmatter` (already true). Add OKF standard fields as first-class concepts:

- Add `description` as a computed/virtual field (derived from excerpt or body truncation)
- Add `okf_resource` JSON column (structured content references)
- Add `okf_type` alias for `collection.slug`

**Pros:** Zero translation overhead. Export/import is identity mapping.
**Cons:** Slightly constrains the CMS data model to OKF conventions.

### B. Adapter Layer (current path, zero migration)

Keep the CMS data model as-is. Build `Okf::Exporter` and `Okf::Importer` as pure serialization adapters.

**Pros:** No schema changes. CMS remains unconstrained.
**Cons:** Small translation overhead on every export/import.

**Recommendation: Start with B.** The mapping is already 1:1. Only move to A if OKF becomes a hard requirement for interoperability.

---

## Implementation Priority

| Priority | Item | Why |
|----------|------|-----|
| P0 | `Okf::Exporter` for collections | Enables Runwell AI to consume CMS knowledge natively |
| P0 | API endpoint `/api/v1/okf/exports` | Same |
| P1 | `Okf::Importer` for collections | Ingest client docs, research, internal knowledge |
| P1 | Internal knowledge collections (`process`, `research`, `runbooks`) | CMS becomes agency memory, not just publishing tool |
| P2 | `Okf::ContextBuilder` for AI prompts | Agent-native context — no JSON translation |
| P2 | Git sync (export + import webhooks) | Content-as-code workflow |
| P3 | `okf.manifest.json` validation | Interop with other OKF consumers |

---

## The Big Picture

OKF isn't a new format to adopt — it's a lens that reveals what the CMS already is:

> A knowledge engine that stores structured markdown documents with validated frontmatter, maintains references between them, versions every change, and publishes them through multiple channels.

By adding OKF export/import, the CMS becomes:
- **An OKF producer** — any agent can consume agency knowledge without API integration
- **An OKF consumer** — external knowledge (research, docs, client assets) flows in naturally
- **A knowledge hub** — public marketing + internal operations knowledge in one place
- **A content-as-code platform** — git-obsidian-vscode workflows supported natively

This directly supports the AI Ecosystem vision: Runwell and CMS don't just share APIs — they share a **knowledge format** that any agent can read, write, and reason about.

# frozen_string_literal: true

module Agents
  # The in-process implementation of the capability catalog.
  #
  # Each capability key in Agents::CapabilityCatalog names a piece of the
  # `cms` CLI the worker harness drives. When a run executes in this process
  # instead (Agents::Runner), the same capabilities are these tool classes —
  # bound to the run, speaking to the models directly, and subject to the
  # same review gate the API applies to a non-publishing token: an edit to
  # anything live becomes a Revision, never a silent write.
  #
  # Kept in one file on purpose: this is a catalog, and the thing that goes
  # wrong with agent tools is drift between what the brief promises and what
  # the tool does. One screen shows all of them.
  module Tools
    # A tool bound to its run, for attribution (revisions, recommendations,
    # review requests all say which run produced them).
    class Base < Lumin::Tool
      def initialize(run)
        @run = run
      end

      private

      attr_reader :run

      def budget = Budget.from(run.brief["budget"])

      # A run started by a person publishes only if that person could:
      # PublicationGate's rule, for the in-process publish tools. A scheduled
      # run has no one behind it; its publish key was checked when it was
      # granted (Agent#validate_publish_grant).
      def publish_refused(capability)
        person = run.triggered_by
        return if person.nil? || person.can?(capability)

        {error: "forbidden", message: "#{person.email} can't publish (#{capability}), so this run can't either."}
      end

      # Writes by an agent never touch a live record directly and never set
      # status. Draft records are edited in place; anything else files a
      # Revision for a person to approve — the same gate the API applies.
      def gated_write(record, attributes)
        attributes = attributes.compact
        if record.respond_to?(:status) && record.status.to_s != "published"
          # An agent never publishes: a draft stays a draft (PublicationGate),
          # whatever the attributes say.
          record.assign_attributes(attributes)
          PublicationGate.withhold(record)
          record.save!
          {status: "updated", draft: true}
        else
          proposal = record.propose(attributes, by: run.triggered_by, source: "agent", run_id: run.id,
            actor: run.triggered_by, note: "Proposed by agent run ##{run.id} (#{run.agent_name})")
          return {status: "unchanged", message: "No content changes."} if proposal.outcome == :unchanged
          # A proposal that couldn't be filed fails the tool call, as it always has.
          raise proposal.error unless proposal.proposed?

          {status: "proposed", revision_id: proposal.revision.id,
           message: "Record is live — change filed for review, not applied."}
        end
      end

      def page_json(page, full: false)
        base = {path: page.path, slug: page.slug, title: page.title, status: page.status,
                locale: page.locale, updated_at: page.updated_at&.iso8601}
        return base unless full

        base.merge(seo: page.seo, frontmatter: page.frontmatter, blocks: page.blocks)
      end

      def entry_json(entry, full: false)
        base = {collection: entry.collection.slug, slug: entry.slug, title: entry.title,
                status: entry.status, locale: entry.locale, updated_at: entry.updated_at&.iso8601}
        return base unless full

        base.merge(seo: entry.seo, frontmatter: entry.frontmatter,
          body_markdown: entry.body_markdown, blocks: entry.blocks)
      end

      def find_page!(path)
        Page.find_by(path: path.to_s) or raise ArgumentError, "no page at path #{path.inspect}"
      end

      def find_collection!(slug)
        Collection.find_by(slug: slug.to_s) or raise ArgumentError, "no collection #{slug.inspect}"
      end

      def find_entry!(collection, slug)
        find_collection!(collection).entries.find_by(slug: slug.to_s) or
          raise ArgumentError, "no entry #{slug.inspect} in #{collection}"
      end
    end

    # --- Read ---------------------------------------------------------------

    class SiteManifest < Base
      description "The shape of this site: collections and their field schemas, " \
                  "block types, globals, and the brand brief (voice, audience, " \
                  "facts that must stay accurate). Read this first."

      def execute
        {
          collections: Collection.all.map { |c|
            {slug: c.slug, name: c.name, entry_count: c.entries.count, schema: c.schema}
          },
          block_types: BlockType.all.map { |bt|
            {slug: bt.slug, label: bt.label, description: bt.description, fields: bt.fields}
          },
          globals: Global.pluck(:slug, :name).map { |slug, name| {slug: slug, name: name} },
          brand: Setting.get("brand")
        }
      end
    end

    class ListPages < Base
      description "Every page: path, title, status. Filter by status to see only published or draft."
      param :status, desc: "published | draft", enum: %w[published draft]

      def execute(status: nil)
        scope = Page.order(:path)
        scope = scope.where(status: status) if status.present?
        {pages: scope.limit(300).map { |p| page_json(p) }}
      end
    end

    class GetPage < Base
      description "One page in full: title, SEO fields, frontmatter and blocks."
      param :path, desc: "The page path, e.g. about/team", required: true

      def execute(path:)
        {page: page_json(find_page!(path), full: true)}
      end
    end

    class ListCollections < Base
      description "The collections and their entry counts."

      def execute
        {collections: Collection.all.map { |c| {slug: c.slug, name: c.name, entry_count: c.entries.count} }}
      end
    end

    class ListEntries < Base
      description "Entries of one collection: slug, title, status."
      param :collection, desc: "Collection slug", required: true
      param :status, desc: "published | draft", enum: %w[published draft]
      param :limit, type: "integer", desc: "Max entries to return (default 100, max 500)"

      def execute(collection:, status: nil, limit: nil)
        scope = find_collection!(collection).entries.order(:slug)
        scope = scope.where(status: status) if status.present?
        {entries: scope.limit((limit || 100).to_i.clamp(1, 500)).map { |e| entry_json(e) }}
      end
    end

    class GetEntry < Base
      description "One collection entry in full: SEO, frontmatter, body and blocks."
      param :collection, desc: "Collection slug", required: true
      param :slug, desc: "Entry slug", required: true

      def execute(collection:, slug:)
        {entry: entry_json(find_entry!(collection, slug), full: true)}
      end
    end

    class ListGlobals < Base
      description "The globals (nav, footer, scripts, site …)."

      def execute
        {globals: Global.all.map { |g| {slug: g.slug, name: g.name, description: g.description} }}
      end
    end

    class GetGlobal < Base
      description "One global's data in full."
      param :slug, desc: "Global slug", required: true

      def execute(slug:)
        global = Global.find_by(slug: slug.to_s) or return {error: "no global #{slug.inspect}"}
        {global: {slug: global.slug, name: global.name, schema: global.schema, data: global.data}}
      end
    end

    class SearchSite < Base
      description "Full-text search across pages and entries. Use before claiming " \
                  "something is missing — a topic may exist under another name."
      param :query, desc: "What to search for", required: true

      def execute(query:)
        cleaned = query.to_s.gsub(/["']/, " ").squeeze(" ").strip
        return {error: "query is blank"} if cleaned.empty?

        fts = %("#{cleaned}")
        {pages: fts_rows(Page, <<~SQL, fts), entries: fts_rows(CollectionEntry, <<~SQL2, fts)}
          SELECT p.path, p.title, p.status,
                 snippet(pages_fts, 2, '[', ']', '…', 12) AS snippet
          FROM pages_fts JOIN pages p ON p.id = pages_fts.rowid
          WHERE pages_fts MATCH ? ORDER BY rank LIMIT 20
        SQL
          SELECT e.slug, c.slug AS collection, e.title, e.status,
                 snippet(collection_entries_fts, 3, '[', ']', '…', 12) AS snippet
          FROM collection_entries_fts
          JOIN collection_entries e ON e.id = collection_entries_fts.rowid
          JOIN collections c ON c.id = e.collection_id
          WHERE collection_entries_fts MATCH ? ORDER BY rank LIMIT 20
        SQL2
      end

      private

      def fts_rows(model, sql, fts)
        model.connection.exec_query(model.send(:sanitize_sql_array, [sql, fts]), "Agent FTS").to_a
      end
    end

    class FindReferences < Base
      description "What links to a record — pages and entries whose content references it. " \
                  "A published record with no references is an orphan."
      param :ref_type, desc: "What is referenced, as references store it: page, asset, a collection's slug (for its entries), or url", required: true
      param :ref_id, desc: "Its id (or, for url, the address)", required: true

      def execute(ref_type:, ref_id:)
        owners = ContentReference.where(ref_type: ref_type.to_s, ref_id: ref_id.to_s)
          .includes(:owner).filter_map(&:owner).uniq
        {references: owners.map { |o|
          {type: o.class.name, id: o.id, title: o.try(:title),
           path: o.try(:path) || o.try(:slug), status: o.try(:status)}
        }}
      end
    end

    class ReadSitemap < Base
      description "The sitemap: every crawlable URL with its source record."

      def execute
        {entries: Sitemap.new.entries.first(500).map { |e| e.to_h.slice(:source, :id, :loc, :lastmod) }}
      end
    end

    class ListRedirects < Base
      description "The redirect rules and their hit counts."

      def execute
        {redirects: Redirect.order(:source_path).limit(300).map { |r|
          {source: r.source_path, destination: r.destination_url, status: r.status_code,
           active: r.active, hits: r.hit_count}
        }}
      end
    end

    # --- Write (review-gated) ----------------------------------------------

    class CreatePage < Base
      description "Create a new page, always as a draft."
      param :slug, desc: "URL slug for the page", required: true
      param :title, desc: "Page title", required: true
      param :parent_path, desc: "Path of the parent page, for nested pages"
      param :locale, desc: "Locale (default en)"

      def execute(slug:, title:, parent_path: nil, locale: nil)
        parent = parent_path.present? ? find_page!(parent_path) : nil
        page = Page.create!(slug: slug, title: title, parent: parent,
          locale: locale.presence || "en", status: "draft")
        {status: "created", page: page_json(page)}
      end
    end

    class UpdatePage < Base
      description "Edit a page's title, SEO, frontmatter or blocks. Drafts are edited " \
                  "in place; published pages get a revision a person must approve. " \
                  "Never changes publish status."
      param :path, desc: "The page path", required: true
      param :title, desc: "New title"
      param :seo, type: "object", desc: "SEO fields (title, description, json_ld …) — replaces the seo object"
      param :frontmatter, type: "object", desc: "Frontmatter — replaces the frontmatter object"
      param :blocks, type: "array", desc: "Block list — replaces the page's blocks", items: {type: "object"}

      def execute(path:, title: nil, seo: nil, frontmatter: nil, blocks: nil)
        gated_write(find_page!(path),
          {title: title, seo: seo, frontmatter: frontmatter, blocks: blocks})
      end
    end

    class CreateEntry < Base
      description "Create a collection entry, always as a draft."
      param :collection, desc: "Collection slug", required: true
      param :slug, desc: "Entry slug", required: true
      param :title, desc: "Entry title", required: true
      param :frontmatter, type: "object", desc: "Frontmatter fields, matching the collection schema"

      def execute(collection:, slug:, title:, frontmatter: nil)
        entry = find_collection!(collection).entries.create!(
          slug: slug, title: title, frontmatter: frontmatter || {}, status: "draft")
        {status: "created", entry: entry_json(entry)}
      end
    end

    class UpdateEntry < Base
      description "Edit an entry's title, SEO, frontmatter, body or blocks. Drafts are " \
                  "edited in place; published entries get a revision a person must " \
                  "approve. Never changes publish status."
      param :collection, desc: "Collection slug", required: true
      param :slug, desc: "Entry slug", required: true
      param :title, desc: "New title"
      param :seo, type: "object", desc: "SEO fields — replaces the seo object"
      param :frontmatter, type: "object", desc: "Frontmatter — replaces the frontmatter object"
      param :body_markdown, desc: "Markdown body — replaces the body"
      param :blocks, type: "array", desc: "Block list — replaces the entry's blocks", items: {type: "object"}

      def execute(collection:, slug:, title: nil, seo: nil, frontmatter: nil, body_markdown: nil, blocks: nil)
        gated_write(find_entry!(collection, slug),
          {title: title, seo: seo, frontmatter: frontmatter,
           body_markdown: body_markdown, blocks: blocks})
      end
    end

    class UpdateGlobal < Base
      description "Propose a change to a global (nav, footer …). Globals are live " \
                  "site-wide, so this always files a revision for a person to approve."
      param :slug, desc: "Global slug", required: true
      param :data, type: "object", desc: "The global's data — replaces the data object", required: true

      def execute(slug:, data:)
        global = Global.find_by(slug: slug.to_s) or return {error: "no global #{slug.inspect}"}
        gated_write(global, {data: data})
      end
    end

    class AddRedirect < Base
      description "Add a redirect rule. Use when a slug changes so the old URL keeps working."
      param :source_path, desc: "The old path, starting with /", required: true
      param :destination_url, desc: "Where it should go — a path or absolute URL", required: true
      param :status_code, type: "integer", desc: "301 (permanent, default) or 302"

      def execute(source_path:, destination_url:, status_code: nil)
        redirect = Redirect.create!(source_path: source_path, destination_url: destination_url,
          status_code: (status_code || 301).to_i, notes: "Added by agent run ##{run.id}")
        {status: "created", id: redirect.id}
      end
    end

    # --- Report back --------------------------------------------------------

    class FileRecommendation < Base
      description "File a finding for a human to decide on. The right move for " \
                  "anything outside this run's remit, or any change that needs a " \
                  "business decision."
      param :kind, desc: "Finding type", required: true, enum: Recommendation::KINDS
      param :title, desc: "One line naming the finding", required: true
      param :body, desc: "The evidence and the concrete fix"
      param :impact, type: "integer", desc: "1–5, how much it matters"
      param :subject_type, desc: "Page or CollectionEntry, when the finding is about one record"
      param :subject_id, type: "integer", desc: "That record's id"

      def execute(kind:, title:, body: nil, impact: nil, subject_type: nil, subject_id: nil)
        cap = budget.proposals
        if run.recommendations.count >= cap
          return {error: "This run's budget allows #{cap} recommendations and they are used. " \
                         "Prioritise — do not file more."}
        end

        subject = find_subject(subject_type, subject_id)
        rec = Recommendation.create!(kind: kind, title: title, body: body,
          impact: (impact || 0).to_i.clamp(0, 5), subject: subject, agent_run: run)
        {status: "filed", recommendation_id: rec.id}
      end

      private

      def find_subject(type, id)
        return nil if type.blank? || id.blank?
        return nil unless %w[Page CollectionEntry Global].include?(type.to_s)

        type.to_s.constantize.find_by(id: id)
      end
    end

    class RequestReview < Base
      description "Ask a human to review and publish a draft you created or edited. " \
                  "Do this once at the end of the run for the work that needs eyes."
      param :record_type, desc: "Page or CollectionEntry", required: true, enum: %w[Page CollectionEntry]
      param :record_id, type: "integer", desc: "The record's id", required: true
      param :comment, desc: "What changed and what the reviewer should check"

      def execute(record_type:, record_id:, comment: nil)
        record = record_type.to_s.constantize.find_by(id: record_id) or
          return {error: "no #{record_type} with id #{record_id}"}
        # A scheduled run has no person behind it; the request is attributed
        # to the oldest admin so `requested_by` (NOT NULL) is honest enough —
        # the review page names the run in the comment.
        requester = run.triggered_by || User.order(:id).first or
          return {error: "no user to attribute the review request to"}

        review = record.review_requests.create!(requested_by: requester,
          comment: ["From agent run ##{run.id} (#{run.agent_name}).", comment.presence].compact.join(" "))
        {status: "requested", review_request_id: review.id}
      end
    end

    # --- Publish (granted deliberately, skips review) ----------------------

    class PublishPage < Base
      description "Publish a page. Only for agents explicitly granted publishing."
      param :path, desc: "The page path", required: true

      def execute(path:)
        refused = publish_refused("pages:publish")
        return refused if refused

        find_page!(path).update!(status: "published", published_at: Time.current)
        {status: "published"}
      end
    end

    class UnpublishPage < Base
      description "Unpublish a page."
      param :path, desc: "The page path", required: true

      def execute(path:)
        refused = publish_refused("pages:publish")
        return refused if refused

        find_page!(path).update!(status: "draft")
        {status: "draft"}
      end
    end

    class SetEntryStatus < Base
      description "Publish or unpublish a collection entry. Only for agents " \
                  "explicitly granted publishing."
      param :collection, desc: "Collection slug", required: true
      param :slug, desc: "Entry slug", required: true
      param :status, desc: "published | draft", required: true, enum: %w[published draft]

      def execute(collection:, slug:, status:)
        refused = publish_refused("entries:publish")
        return refused if refused

        entry = find_entry!(collection, slug)
        attrs = {status: status}
        attrs[:published_at] = Time.current if status == "published"
        entry.update!(attrs)
        {status: status}
      end
    end

    # Capability key → tool classes. Keys with no in-process implementation
    # yet (assets, schema edits, deploys, submissions, webhooks, audit log)
    # simply contribute nothing: the brief still states them, and the worker
    # path still covers them in full.
    CATALOG = {
      "manifest" => [SiteManifest],
      "read_pages" => [ListPages, GetPage],
      "read_entries" => [ListCollections, ListEntries, GetEntry],
      "read_globals" => [ListGlobals, GetGlobal],
      "search" => [SearchSite],
      "references" => [FindReferences],
      "sitemap" => [ReadSitemap],
      "read_redirects" => [ListRedirects],
      "write_pages" => [CreatePage, UpdatePage],
      "write_entries" => [CreateEntry, UpdateEntry],
      "write_globals" => [UpdateGlobal],
      "write_redirects" => [AddRedirect],
      "recommend" => [FileRecommendation],
      "review_request" => [RequestReview],
      "publish_pages" => [PublishPage, UnpublishPage],
      "publish_entries" => [SetEntryStatus]
    }.freeze

    module_function

    # The tool instances for one run, from the capability keys stamped into
    # its brief — the frozen snapshot, not the agent's current row, so an
    # agent edited mid-queue runs with the capabilities it was dispatched with.
    def for_run(run)
      keys = Array(run.brief.dig("capabilities")).map { |c| c.is_a?(Hash) ? c["key"] : c.to_s }
      keys = Array(run.agent&.capability_keys) if keys.empty?
      catalog = CATALOG.merge(Cms::Plugins.enabled_agent_tools)
      keys.uniq.flat_map { |key| Array(catalog[key]) }.uniq.map { |klass| klass.new(run) }
    end
  end
end

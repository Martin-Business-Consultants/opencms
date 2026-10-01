# frozen_string_literal: true

module Reports
  module Definitions
    # Does the live site do what the CMS says it should?
    #
    # The other Site health reports ask a crawler what it thinks of the
    # pages. This one asks a different question: the CMS knows which tags
    # should load and how consent gates them (Scripts, Consent), which forms
    # exist and where they post (Forms), what the business's phone number is
    # (Reporting), and what the site's URL is — so it can render the live
    # pages and compare. Every finding is the gap between the two, in words
    # a marketer can act on, with a link to the page in the CMS that fixes
    # it when the fix is here.
    #
    # DataForSEO's instant_pages endpoint renders each page in a real
    # browser and runs our probe (Audit::Probe) inside it: that is how the
    # audit sees tags a tag manager injected, cookies set before consent,
    # and the phone number a call-tracking script swapped in. The home page
    # is rendered twice — once plain, once as a Google Ads click — because
    # that second visit is the one dynamic number insertion exists for.
    class SiteAudit < Definition
      PATH = "on_page/instant_pages"
      MAX_PAGES = 6

      # A gclid Google would never issue, so a real campaign can't be
      # credited with the audit's own visit.
      PAID_QUERY = "gclid=LuminAudit000&utm_source=google&utm_medium=cpc&utm_campaign=site-audit"

      def self.title = "Site audit"

      def self.description
        "The live site against what the CMS expects: tags and consent, the phone number and call tracking, " \
        "every form end to end, and whether Google can find and verify the site."
      end

      def self.group = "Site health"
      def self.requires = [:audit_urls]
      def self.estimated_cost = 0.05
      def self.cadence = "weekly"
      def self.location_granularity = :none

      def self.trend_metrics
        [
          {key: "findings", label: "Findings", good: "down"},
          {key: "critical", label: "Critical", good: "down"},
          {key: "high", label: "High", good: "down"},
          {key: "passed", label: "Checks passed", good: "up"}
        ]
      end

      def self.trend_point(data)
        counts = data["counts"] || {}
        {
          "findings" => Array(data["findings"]).length,
          "critical" => counts["critical"].to_i,
          "high" => counts["high"].to_i,
          "passed" => Array(data["passed"]).length
        }
      end

      # What a person has dismissed, keyed by finding key — kept in settings
      # rather than on the snapshot so it survives the next run.
      def self.page_props
        {dismissed: Dismissals.all}
      end

      def call
        base_url = profile.base_url
        urls = page_urls(base_url)
        paid_url = "#{base_url}/?#{PAID_QUERY}"

        # One call per page rather than a batch: `fetch` drops an optional
        # field the endpoint refuses and tries again, and a page that still
        # fails keeps DataForSEO's own sentence about why. A batch returns
        # nil for a failed task and the reason is gone.
        pages = urls.map { |url| render(url) }
        paid = render(paid_url)

        context = Audit::Context.new(
          profile: profile, base_url: base_url, pages: pages, paid: paid,
          fetches: fetches(base_url),
          # From the plugins that hold them (Consent & Scripts, Forms); nil
          # and empty while those are off.
          consent: Cms::Plugins.provided(:consent_config),
          scripts: Array(Cms::Plugins.provided(:scripts)),
          forms: Array(Cms::Plugins.provided(:published_forms))
        )
        findings = Audit::Findings.new

        # The analyzers that read the rendered page have nothing to read when
        # nothing rendered; Search still runs its plain-GET half and files
        # the render failure itself, with DataForSEO's reason.
        tracking = Audit::Tracking.new(context, findings).call
        phones = Audit::Phones.new(context, findings).call
        forms = Audit::Forms.new(context, findings).call
        search = Audit::Search.new(context, findings).call

        sorted = findings.sorted
        {
          base_url: base_url,
          audited_at: Time.current.iso8601,
          pages: pages.map { |p| p.except(:probe) },
          paid_page: paid.except(:probe),
          tracking: tracking,
          phones: phones,
          forms: forms[:forms],
          unknown_forms: forms[:unknown_forms],
          search: search,
          findings: sorted,
          passed: findings.passed,
          counts: findings.counts,
          narrative: Audit::Narrative.call(findings: sorted, passed: findings.passed, business: profile.business_name)
        }
      end

      private

      # The home page first, then the configured audit URLs — the contact and
      # service pages a person listed — with duplicates and other hosts
      # dropped. Capped: each render is paid for.
      def page_urls(base_url)
        home = "#{base_url}/"
        others = profile.audit_urls.map { |u| u.to_s.strip }.reject(&:empty?)
        ([home] + others).map { |u| u.chomp("/") + (u.end_with?("/") || u == base_url ? "/" : "") }
                         .uniq { |u| u.chomp("/") }.first(MAX_PAGES)
      end

      def render(url)
        page_for(url, fetch(PATH, task_for(url)))
      rescue DataForSeo::Error => e
        warnings << "#{url}: #{e.message}"
        {url: url, error: e.message, probe_ran: false}
      end

      def task_for(url)
        {
          url: url,
          enable_javascript: true,
          enable_xhr: true,
          load_resources: true,
          browser_preset: "mobile",
          accept_language: "en-US",
          return_despite_timeout: true,
          custom_js: Audit::Probe::SCRIPT
        }
      end

      def page_for(url, response)
        return {url: url, error: "DataForSEO returned no result for this page", probe_ran: false} if response.nil? || response.empty?

        item = Array(response.first["items"]).first
        return {url: url, error: "DataForSEO returned no page item", probe_ran: false} if item.nil?

        meta = item["meta"] || {}
        {
          url: item["url"].presence || url,
          status_code: item["status_code"],
          onpage_score: round(item["onpage_score"], 1),
          title: meta["title"].to_s,
          fetch_time: item["fetch_time"],
          probe: Audit::Probe.read(item["custom_js_response"]),
          probe_ran: !Audit::Probe.read(item["custom_js_response"]).nil?
        }
      end

      # The plain GETs, from this server. Each is one request and none can
      # raise; a site that is down shows up as findings, not a failed report.
      def fetches(base_url)
        uri = URI.parse(base_url)
        host = uri.host.to_s
        alt_host = host.start_with?("www.") ? host.delete_prefix("www.") : "www.#{host}"
        {
          home: Audit::Fetch.get(base_url),
          robots: Audit::Fetch.get("#{base_url}/robots.txt"),
          sitemap: Audit::Fetch.get("#{base_url}/sitemap.xml"),
          alt_host: Audit::Fetch.get("#{uri.scheme}://#{alt_host}/", follow: 0)
        }
      rescue URI::InvalidURIError
        {}
      end
    end
  end
end

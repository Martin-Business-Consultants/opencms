# frozen_string_literal: true

module Reports
  module Definitions
    # Technical SEO for the pages that matter, crawled live.
    #
    # The instant_pages endpoint is the cheap half of DataForSEO's OnPage
    # API: no crawl to queue, no task to poll, up to 20 URLs in one call. For
    # a local site — a home page, a services page, a contact page, one page
    # per town — that is the whole site, so a full crawler would be paying
    # for machinery this doesn't need.
    #
    # The response carries 60-odd boolean checks. Passing them all through
    # would produce a wall of red that nobody reads, so only the checks that
    # change what Google does are kept, sorted by whether they break the page,
    # hide it, or merely make it worse.
    class PageHealth < Definition
      PATH = "on_page/instant_pages"

      # The endpoint's own batch limit.
      MAX_URLS = 20

      # `check_name => [severity, human sentence]`. The wording is the
      # report — a check named `no_h1_tag` means nothing to the person
      # deciding whether to pay for the fix.
      CHECKS = {
        "is_5xx_code"                 => [:critical, "Server error — the page doesn't load"],
        "is_4xx_code"                 => [:critical, "Page not found"],
        "is_broken"                   => [:critical, "Page is broken"],
        "is_redirect"                 => [:medium,   "Page redirects somewhere else"],
        "no_title"                    => [:critical, "No title tag"],
        "no_description"              => [:high,     "No meta description"],
        "no_h1_tag"                   => [:high,     "No H1 heading"],
        "title_too_long"              => [:medium,   "Title is too long and will be truncated"],
        "title_too_short"             => [:low,      "Title is very short"],
        "duplicate_title_tag"         => [:high,     "Title is duplicated elsewhere on the site"],
        "duplicate_meta_tags"         => [:medium,   "Meta tags are duplicated elsewhere"],
        "no_image_alt"                => [:medium,   "Images are missing alt text"],
        "is_http"                     => [:critical, "Served over HTTP, not HTTPS"],
        "https_to_http_links"         => [:high,     "Secure page links out to insecure URLs"],
        "high_loading_time"           => [:high,     "Page is slow to load"],
        "high_waiting_time"           => [:medium,   "Server is slow to respond"],
        "has_render_blocking_resources" => [:medium, "Render-blocking scripts or styles"],
        "size_greater_than_3mb"       => [:medium,   "Page weighs over 3MB"],
        "low_content_rate"            => [:medium,   "Very little text relative to markup"],
        "low_character_count"         => [:medium,   "Thin content"],
        "no_favicon"                  => [:low,      "No favicon"],
        "no_doctype"                  => [:low,      "Missing doctype"],
        "seo_friendly_url"            => [:low,      "URL isn't SEO-friendly", :inverted],
        "has_micromarkup"             => [:medium,   "No structured data (schema.org)", :inverted],
        "has_micromarkup_errors"      => [:high,     "Structured data has errors"],
        "lorem_ipsum"                 => [:high,     "Placeholder text left on the page"],
        "has_misspelling"             => [:low,      "Spelling mistakes detected"]
      }.freeze

      SEVERITY_ORDER = {"critical" => 0, "high" => 1, "medium" => 2, "low" => 3}.freeze

      def self.title = "Page health"

      def self.description
        "A live technical crawl of the key pages — status, titles, headings, " \
        "structured data, speed and Core Web Vitals."
      end

      def self.group = "Site health"
      def self.requires = [:audit_urls]
      def self.estimated_cost = 0.03
      def self.cadence = "weekly"

      # A crawl happens at a URL; there is no location in the request at all.
      def self.location_granularity = :none

      def self.trend_metrics
        [
          {key: "average_score", label: "Average score", good: "up"},
          {key: "issues", label: "Issues", good: "down"},
          {key: "critical", label: "Critical", good: "down"},
          {key: "pages", label: "Pages crawled", good: nil}
        ]
      end

      def self.trend_point(data)
        pages = Array(data["pages"]).reject { |page| page["error"] }
        issues = pages.flat_map { |page| Array(page["issues"]) }
        {
          "average_score" => data["average_score"]&.to_f,
          "issues" => issues.length,
          "critical" => issues.count { |issue| issue["severity"] == "critical" },
          "pages" => pages.length
        }
      end

      def call
        urls = profile.audit_urls.first(MAX_URLS)
        responses = fetch_many(PATH, urls.map { |url| task_for(url) })
        pages = urls.zip(responses).map { |url, response| page_for(url, response) }
        scored = pages.reject { |page| page[:error] }

        {
          pages: pages.sort_by { |page| page[:onpage_score] || 0 },
          average_score: scored.any? ? round(scored.sum { |p| p[:onpage_score].to_f } / scored.length, 1) : nil,
          # Which problems are site-wide rather than page-specific. A title
          # length issue on one page is an edit; on nine pages it's a template.
          recurring_issues: recurring(scored)
        }
      end

      private

      # Browser rendering costs extra and is the only way to get LCP/CLS.
      # Worth it: for a local site, speed on mobile is frequently the single
      # biggest technical problem, and without rendering the report would
      # confidently report a fast page that takes six seconds to paint.
      def task_for(url)
        {
          url: url,
          browser_preset: "mobile",
          enable_browser_rendering: true,
          validate_micromarkup: true
        }
      end

      def page_for(url, response)
        return {url: url, error: "Could not be crawled"} if response.nil? || response.empty?

        item = Array(response.first["items"]).first
        return {url: url, error: "No crawl result"} if item.nil?

        meta = item["meta"] || {}
        timing = item["page_timing"] || {}

        {
          url: item["url"].presence || url,
          status_code: item["status_code"],
          onpage_score: round(item["onpage_score"], 1),
          title: meta["title"].to_s,
          title_length: meta["title_length"].to_i,
          description: meta["description"].to_s,
          description_length: meta["description_length"].to_i,
          canonical: meta["canonical"].to_s,
          h1: Array(meta.dig("htags", "h1")).first.to_s,
          word_count: meta["plain_text_word_count"] || item.dig("content", "plain_text_word_count"),
          internal_links: meta["internal_links_count"].to_i,
          external_links: meta["external_links_count"].to_i,
          images: meta["images_count"].to_i,
          size_kb: item["size"].to_i.positive? ? (item["size"].to_i / 1024.0).round : nil,
          # Core Web Vitals, in milliseconds as returned. Named as Google
          # names them so the numbers can be compared with PageSpeed.
          lcp: timing["largest_contentful_paint"],
          cls: meta["cumulative_layout_shift"],
          ttfb: timing["waiting_time"],
          time_to_interactive: timing["time_to_interactive"],
          issues: issues(item["checks"] || {}),
          resource_errors: Array(item.dig("resource_errors", "errors")).length
        }
      end

      # Most checks are "true means bad". A few (`seo_friendly_url`,
      # `has_micromarkup`) are "true means good" — flagged `:inverted` in the
      # table rather than handled with a special case per check.
      def issues(checks)
        CHECKS.filter_map do |name, (severity, message, inverted)|
          value = checks[name]
          next if value.nil?

          failed = inverted ? !value : value
          next unless failed

          {check: name, severity: severity.to_s, message: message}
        end.sort_by { |issue| SEVERITY_ORDER.fetch(issue[:severity], 9) }
      end

      def recurring(pages)
        return [] if pages.length < 2

        pages
          .flat_map { |page| Array(page[:issues]) }
          .group_by { |issue| issue[:check] }
          .select { |_, occurrences| occurrences.length > 1 }
          .map do |check, occurrences|
            {
              check: check,
              severity: occurrences.first[:severity],
              message: occurrences.first[:message],
              pages: occurrences.length
            }
          end
          .sort_by { |issue| [SEVERITY_ORDER.fetch(issue[:severity], 9), -issue[:pages]] }
      end
    end
  end
end

# frozen_string_literal: true

module Reports
  module Audit
    # Can Google find, read and trust the site — and is Search Console in
    # the picture?
    #
    # Everything here is what a crawler sees from outside: robots.txt, the
    # sitemap, the verification tag, canonical and robots meta, one host
    # spelling redirecting to the other, HTTPS, structured data. A Search
    # Console *connection* would need a Google login the CMS doesn't hold;
    # what the CMS can see is whether the site is verifiable, and it says so.
    class Search
      LOCAL_TYPES = /LocalBusiness|Organization|Store|Dentist|Physician|Attorney|LegalService|Plumber|Electrician|HVACBusiness|HomeAndConstructionBusiness|Restaurant|AutoRepair|SelfStorage|RealEstateAgent|ProfessionalService|MedicalBusiness|FinancialService|Hotel|LodgingBusiness/

      def initialize(context, findings)
        @ctx = context
        @out = findings
      end

      def call
        home = @ctx.home
        probe = @ctx.probe(home)
        meta = probe["meta"] || {}
        robots = @ctx.fetches[:robots]
        sitemap = @ctx.fetches[:sitemap]
        alt = @ctx.fetches[:alt_host]
        home_fetch = @ctx.fetches[:home]

        page_findings(home, home_fetch)
        robots_data = robots_findings(robots)
        sitemap_data = sitemap_findings(sitemap, robots_data)
        alt_data = alt_host_findings(alt)
        # The meta-tag checks read the rendered home page. When it didn't
        # render there is nothing to read, and "no viewport tag" would be a
        # statement about a page nobody saw.
        if home && home[:probe]
          verification_findings(meta)
          meta_findings(meta, home_fetch)
          schema_findings(probe["jsonld"])
        end

        {
          verification: meta["verification"].present?,
          canonical: meta["canonical"], robots_meta: meta["robots"], viewport: meta["viewport"].present?,
          robots: robots_data, sitemap: sitemap_data, alt_host: alt_data,
          jsonld_types: probe["jsonld"].uniq,
          x_robots_tag: home_fetch&.headers&.dig("x-robots-tag")
        }
      end

      private

      def page_findings(home, fetch)
        status = home && home[:status_code]
        if status && status != 200
          @out.add(key: "pages:home-status", area: "pages", severity: "critical",
                   title: "The home page answers #{status}",
                   body: "Google and visitors get the same. Fix the deploy or the redirect before anything else on this list matters.",
                   fix: {label: "In the site's hosting"})
        elsif home.nil? || home[:error]
          @out.add(key: "pages:home-unreachable", area: "pages", severity: "critical",
                   title: "The home page couldn't be rendered",
                   body: "DataForSEO's browser returned no page. It said: #{home&.dig(:error).to_s.presence || "nothing"}. " \
                         "Until it renders, the tag, consent, phone and form checks can't run — only what a plain request sees is below. " \
                         "Check the site loads at #{@ctx.base_url} and that the URL in Settings → General is the public one.",
                   fix: {label: "General settings", href: "/settings/general"}, evidence: {error: home&.dig(:error)})
        elsif home[:probe].nil?
          @out.add(key: "pages:probe-failed", area: "pages", severity: "critical",
                   title: "The home page rendered, but the audit's script didn't run in it",
                   body: "DataForSEO returned the page without our probe's answer — usually the endpoint refused `custom_js` (the snapshot's warnings say so) " \
                         "or the page took too long to finish loading its scripts. Without it the tag, consent, phone and form checks can't run. Run the audit again; if it repeats, the page is slow to become interactive.",
                   fix: {label: "Run again", href: "/reports"})
        else
          @out.pass(key: "pages:home", area: "pages", title: "Home page loads (200)")
        end

        return unless @ctx.base_url.start_with?("http://") || (fetch&.url.to_s.start_with?("http://") && !fetch.redirects.to_a.any?)

        @out.add(key: "search:https", area: "search", severity: "critical",
                 title: "The site isn't served over HTTPS",
                 body: "Browsers mark it “not secure” and Google ranks it down. Turn on TLS at the host and set the site URL to https://.",
                 fix: {label: "General settings", href: "/settings/general"})
      end

      def robots_findings(fetch)
        return {status: nil, error: fetch&.error} if fetch.nil? || fetch.error

        body = fetch.body.to_s
        blocks_all = body.match?(/^user-agent:\s*\*\s*$.*?^disallow:\s*\/\s*$/mi) && !body.match?(/^allow:\s*\/\s*$/mi)
        sitemap_refs = body.scan(/^sitemap:\s*(\S+)/i).flatten

        if fetch.status == 404
          @out.add(key: "search:robots-missing", area: "search", severity: "low",
                   title: "No robots.txt",
                   body: "Not fatal — crawlers assume everything is allowed — but it's where the sitemap gets announced. Add one with a Sitemap: line.",
                   fix: {label: "In the site's code"})
        elsif blocks_all
          @out.add(key: "search:robots-blocks", area: "search", severity: "critical",
                   title: "robots.txt blocks the whole site",
                   body: "`Disallow: /` for every crawler. Usually a staging setting that shipped. Nothing on the site can rank until it's removed.",
                   fix: {label: "In the site's code"}, evidence: {robots: body.lines.first(8).map(&:strip)})
        elsif fetch.ok?
          @out.pass(key: "search:robots", area: "search", title: "robots.txt is present and doesn't block crawling")
        end

        {status: fetch.status, blocks_all: blocks_all, sitemap_refs: sitemap_refs}
      end

      def sitemap_findings(fetch, robots)
        return {status: nil, error: fetch&.error} if fetch.nil? || fetch.error

        urls = fetch.ok? ? fetch.body.to_s.scan(%r{<loc>\s*([^<\s]+)\s*</loc>}i).flatten : []
        same_host = urls.any? && urls.all? { |u| host_of(u) == @ctx.host }

        if !fetch.ok?
          @out.add(key: "search:sitemap-missing", area: "search", severity: "medium",
                   title: "No sitemap.xml at the site",
                   body: "Google finds pages faster and more completely with one. The CMS publishes a sitemap for this site; have the site serve or proxy it at /sitemap.xml and list it in robots.txt.",
                   fix: {label: "Sitemap", href: "/sitemap"})
        elsif urls.empty?
          @out.add(key: "search:sitemap-empty", area: "search", severity: "medium",
                   title: "sitemap.xml has no URLs in it",
                   body: "It answers, but lists nothing — often a build that ran before content published.",
                   fix: {label: "Sitemap", href: "/sitemap"})
        else
          @out.pass(key: "search:sitemap", area: "search", title: "sitemap.xml lists #{urls.length} URL#{"s" unless urls.length == 1}")
          unless same_host
            @out.add(key: "search:sitemap-host", area: "search", severity: "medium",
                     title: "sitemap.xml lists URLs on a different host",
                     body: "The sitemap points at #{urls.map { |u| host_of(u) }.uniq.first(2).join(", ")} while the site is #{@ctx.host}. Google ignores entries that don't match the host that served the sitemap.",
                     fix: {label: "General settings", href: "/settings/general"})
          end
          if robots[:status].to_i == 200 && Array(robots[:sitemap_refs]).empty?
            @out.add(key: "search:sitemap-unannounced", area: "search", severity: "low",
                     title: "robots.txt doesn't mention the sitemap",
                     body: "Add `Sitemap: #{@ctx.base_url}/sitemap.xml` so crawlers find it without Search Console.",
                     fix: {label: "In the site's code"})
          end
        end

        {status: fetch.status, url_count: urls.length, same_host: same_host}
      end

      def verification_findings(meta)
        if meta["verification"].present?
          @out.pass(key: "search:verification", area: "search", title: "Search Console verification tag is on the home page")
        else
          @out.add(key: "search:verification", area: "search", severity: "medium",
                   title: "No Search Console verification tag found",
                   body: "There's no google-site-verification meta tag. If the property is verified through DNS this is fine — dismiss it. If nobody has verified the site, Search Console has no data for it and indexing problems go unseen.",
                   fix: {label: "In the site's code"})
        end
      end

      def meta_findings(meta, fetch)
        robots_meta = [meta["robots"], fetch&.headers&.dig("x-robots-tag")].compact.join(",").downcase
        if robots_meta.include?("noindex")
          @out.add(key: "search:noindex", area: "search", severity: "critical",
                   title: "The home page is marked noindex",
                   body: "Google is told to drop it. Almost always a staging flag left on. Remove the robots meta or header.",
                   fix: {label: "In the site's code"}, evidence: {robots: robots_meta})
        end

        canonical_host = host_of(meta["canonical"])
        if meta["canonical"].present? && canonical_host.present? && canonical_host != @ctx.host
          @out.add(key: "search:canonical", area: "search", severity: "high",
                   title: "The home page's canonical points at #{canonical_host}",
                   body: "It tells Google the real page lives elsewhere — a leftover from staging or an old domain. Canonicals should point at #{@ctx.host}.",
                   fix: {label: "In the site's code"}, evidence: {canonical: meta["canonical"]})
        elsif meta["canonical"].present?
          @out.pass(key: "search:canonical", area: "search", title: "Canonical URL points at this site")
        end

        return if meta["viewport"].present?

        @out.add(key: "search:viewport", area: "search", severity: "high",
                 title: "No viewport meta tag — the site isn't mobile-friendly",
                 body: "Without it phones render the desktop layout shrunk down. Google indexes mobile-first; this costs rankings and calls.",
                 fix: {label: "In the site's code"})
      end

      def alt_host_findings(fetch)
        return nil if fetch.nil?
        return {host: host_of(fetch.url), error: fetch.error} if fetch.error

        target = fetch.location && host_of(URI.join(fetch.url, fetch.location).to_s)
        redirects_home = fetch.redirect? && target == @ctx.host
        # The two spellings, as typed — stripping www would make them the same word.
        this_host = URI.parse(@ctx.base_url).host.to_s
        other_host = URI.parse(fetch.url).host.to_s
        if redirects_home
          @out.pass(key: "search:alt-host", area: "search", title: "#{other_host} redirects to #{this_host}")
        elsif fetch.ok?
          @out.add(key: "search:alt-host", area: "search", severity: "medium",
                   title: "Both #{other_host} and #{this_host} serve the site",
                   body: "Two copies of every page split links and confuse Google about which to rank. Redirect one host to the other permanently (301).",
                   fix: {label: "In the site's hosting"})
        end

        {host: other_host, status: fetch.status, redirects_to: target}
      rescue URI::InvalidURIError
        {host: fetch.url, status: fetch.status}
      end

      def schema_findings(types)
        if types.any? { |t| t.match?(LOCAL_TYPES) }
          @out.pass(key: "search:schema", area: "search", title: "Structured data names the business (#{types.grep(LOCAL_TYPES).first})")
        elsif types.include?("invalid")
          @out.add(key: "search:schema-invalid", area: "search", severity: "medium",
                   title: "Structured data on the home page doesn't parse",
                   body: "A JSON-LD block isn't valid JSON, so Google reads none of it.",
                   fix: {label: "Pages", href: "/pages"})
        else
          @out.add(key: "search:schema", area: "search", severity: "medium",
                   title: "No LocalBusiness structured data on the home page",
                   body: "Schema.org markup naming the business, address, phone and hours is how Google confirms the site and the listing are the same place. The page SEO panel can emit it.",
                   fix: {label: "Pages", href: "/pages"}, evidence: {types: types})
        end
      end

      def host_of(url)
        URI.parse(url.to_s).host.to_s.sub(/\Awww\./, "")
      rescue URI::InvalidURIError
        ""
      end
    end
  end
end

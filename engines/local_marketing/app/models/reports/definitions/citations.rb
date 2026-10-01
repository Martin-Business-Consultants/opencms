# frozen_string_literal: true

module Reports
  module Definitions
    # Where the business is listed, and whether every listing agrees.
    #
    # A citation is the business's name, address and phone on somebody else's
    # site — a directory, a map, a review site. Google cross-checks them:
    # ten listings that agree are trust, ten that disagree about the phone
    # number are noise, and a missing listing on a directory Google leans on
    # is a gap the competitor next door has filled.
    #
    # No API audits citations, so this one is built from two that exist. For
    # each directory, one Google search scoped to that site finds the listing
    # (or doesn't); one content-parsing call reads the listing and checks the
    # name, the phone and the address against the NAP. Two directories that
    # hide from Google — Apple Maps, Bing Places — are listed as manual, with
    # the reason, rather than shown as missing.
    #
    # What a person has DONE about each directory lives in settings, not
    # here: it changes without a paid run. See Reports::CitationStatuses.
    class Citations < Definition
      SEARCH = "serp/google/organic/live/advanced"
      PARSE = "on_page/content_parsing/live"

      # Directories Google search can't see into. Managed by hand; the report
      # says so instead of calling them missing.
      MANUAL_ONLY = {
        "bingplaces.com" => "Bing Places listings aren't indexed by Google — check at bingplaces.com.",
        "maps.apple.com" => "Apple Maps listings aren't indexed by Google — check in Apple Business Connect."
      }.freeze

      MAX_DIRECTORIES = 20

      def self.title = "Citations"

      def self.description
        "Whether the business is listed on the directories that matter, and whether each " \
        "listing's name, address and phone agree with Google's — with a checklist for the fixes."
      end

      def self.group = "Local"
      def self.requires = [:business_name]
      def self.estimated_cost = 0.03
      def self.cadence = "monthly"
      # A `site:` search barely cares where it's run from; the country code
      # is enough and never rejected.
      def self.location_granularity = :country
      def self.locations_api = "dataforseo_labs"

      def self.trend_metrics
        [
          {key: "found", label: "Listed", good: "up"},
          {key: "consistent", label: "NAP consistent", good: "up"},
          {key: "missing", label: "Missing", good: "down"},
          {key: "inconsistent", label: "NAP differs", good: "down"}
        ]
      end

      def self.trend_point(data)
        rows = Array(data["directories"]).reject { |d| d["manual_only"] }
        {
          "found" => rows.count { |d| d["found"] },
          "consistent" => rows.count { |d| d["consistent"] },
          "missing" => rows.count { |d| !d["found"] },
          "inconsistent" => rows.count { |d| d["found"] && !d["consistent"] }
        }
      end

      # The manual statuses ride along on the page, not on the snapshot.
      def self.page_props
        {citation_statuses: Reports::CitationStatuses.all}
      end

      def call
        nap = reference_nap
        directories = profile.citation_directories.first(MAX_DIRECTORIES)
        rows = directories.map { |domain| MANUAL_ONLY.key?(domain) ? manual_row(domain) : audit(domain, nap) }
        auditable = rows.reject { |r| r[:manual_only] }

        locale_data.merge(
          nap: nap,
          nap_source: nap[:source],
          directories: rows,
          checked: auditable.length,
          found: auditable.count { |r| r[:found] },
          consistent: auditable.count { |r| r[:consistent] },
          missing: auditable.reject { |r| r[:found] }.map { |r| r[:domain] },
          inconsistent: auditable.select { |r| r[:found] && !r[:consistent] }.map { |r| r[:domain] }
        )
      end

      private

      # The NAP everything is checked against. Settings win when set;
      # otherwise the latest Business profile snapshot — Google's version,
      # which is the one the other directories are compared to anyway.
      def reference_nap
        gbp = Report.latest_by_kind["business_profile"]&.data || {}
        phone = profile.phone.presence || gbp["phone"].to_s
        address = profile.address.presence || gbp["address"].to_s
        {
          name: profile.business_name,
          phone: phone,
          address: address,
          source: profile.phone.present? || profile.address.present? ? "settings" : (gbp.present? ? "business_profile" : "none")
        }
      end

      def manual_row(domain)
        {domain: domain, label: domain, manual_only: true, reason: MANUAL_ONLY[domain],
         found: nil, consistent: nil, url: nil, title: nil, checks: {}}
      end

      def audit(domain, nap)
        listing = find_listing(domain)
        return {domain: domain, label: domain, manual_only: false, found: false, consistent: false, url: nil, title: nil, checks: {}} if listing.nil?

        checks = check_nap(listing[:url], nap)
        {
          domain: domain,
          label: domain,
          manual_only: false,
          found: true,
          url: listing[:url],
          title: listing[:title],
          checks: checks,
          # Consistent means everything we could check agrees. A check we
          # couldn't run (no reference phone, say) neither passes nor fails.
          consistent: checks.values.compact.all?,
          unchecked: checks.select { |_, v| v.nil? }.keys
        }
      end

      # One search scoped to the directory. The first organic result on that
      # domain is the listing; a page from another domain is Google being
      # helpful, not a citation.
      def find_listing(domain)
        city = profile.location_name.split(",").first.to_s.strip
        query = %(site:#{domain} "#{profile.business_name}" #{city}).strip
        response = fetch(SEARCH, locale_params.merge(keyword: query, depth: 10, device: "desktop"))
        items = Array(response.first&.dig("items")).select { |i| i["type"] == "organic" }
        hit = items.find { |i| host_of(i["url"]).to_s.end_with?(domain) }
        hit && {url: hit["url"].to_s, title: hit["title"].to_s}
      rescue DataForSeo::Error => e
        warnings << "#{domain}: search failed — #{e.message.truncate(120)}"
        nil
      end

      # Reads the listing and looks for each part of the NAP in it. nil for
      # a part we have no reference for, or a page we couldn't read.
      def check_nap(url, nap)
        response = fetch(PARSE, {url: url, markdown_view: true, disable_cookie_popup: true})
        item = Array(response.first&.dig("items")).first || {}
        text = item["page_as_markdown"].presence || strings_in(item["page_content"]).join(" ")
        norm = normalize(text)

        {
          name: nap[:name].present? ? norm.include?(normalize(nap[:name])) : nil,
          phone: nap[:phone].present? ? digits(text).include?(digits(nap[:phone]).last(10)) : nil,
          address: nap[:address].present? ? address_matches?(norm, nap[:address]) : nil
        }
      rescue DataForSeo::Error => e
        warnings << "#{host_of(url)}: couldn't read the listing — #{e.message.truncate(120)}"
        {name: nil, phone: nil, address: nil}
      end

      # Addresses are written a dozen ways. The street number plus the ZIP
      # (or the first significant token) agreeing is the honest bar.
      def address_matches?(norm, address)
        parts = normalize(address).split(/\s+/)
        number = parts.find { |p| p.match?(/\A\d+\z/) }
        zip = parts.reverse.find { |p| p.match?(/\A\d{5}\z/) }
        anchors = [number, zip].compact
        anchors = parts.reject { |p| p.length < 4 }.first(2) if anchors.empty?
        anchors.any? && anchors.all? { |a| norm.include?(a) }
      end

      def normalize(value)
        value.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").squeeze(" ").strip
      end

      def digits(value) = value.to_s.gsub(/\D/, "")

      def host_of(url)
        URI.parse(url.to_s).host&.downcase&.sub(/\Awww\./, "")
      rescue URI::InvalidURIError
        nil
      end

      # Every string in a nested structure, in order — the fallback when the
      # markdown view isn't there.
      def strings_in(node)
        case node
        when String then [node]
        when Array then node.flat_map { |n| strings_in(n) }
        when Hash then node.values.flat_map { |n| strings_in(n) }
        else []
        end
      end
    end
  end
end

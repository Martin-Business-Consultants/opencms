# frozen_string_literal: true

module Reports
  module Audit
    # Everything the analyzers read, gathered once.
    #
    # `pages` are the rendered probes, home page first. `paid` is the home
    # page rendered a second time with a Google Ads click in the URL — the
    # visit a call-tracking script swaps the number for. `fetches` are the
    # plain GETs (robots, sitemap, the other host spelling).
    Context = Struct.new(:profile, :base_url, :pages, :paid, :fetches, :consent, :scripts, :forms, keyword_init: true) do
      def home = pages.first

      # The probe of a page, or an empty one for a page that didn't render —
      # so an analyzer can read `probe(page)["forms"]` without a guard.
      def probe(page)
        (page && page[:probe]) || Probe::EMPTY
      end

      def rendered = pages.select { |p| p[:probe] }

      def host
        URI.parse(base_url).host.to_s.sub(/\Awww\./, "")
      rescue URI::InvalidURIError
        ""
      end
    end
  end
end

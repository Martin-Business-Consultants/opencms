# frozen_string_literal: true

require "net/http"

module Reports
  module Audit
    # A plain GET from this server, for the things a rendered page can't
    # tell you: robots.txt, the sitemap, response headers, and where the
    # other spelling of the host sends people.
    #
    # Small on purpose. It follows a few redirects, reads half a megabyte at
    # most, and never raises — a site that is down is a finding, not an
    # exception, and the audit has to finish to say so.
    module Fetch
      Result = Struct.new(:url, :status, :body, :headers, :redirects, :error, keyword_init: true) do
        def ok? = status.to_i.between?(200, 299)
        def redirect? = status.to_i.between?(300, 399)
        def location = headers && headers["location"]
      end

      OPEN_TIMEOUT = 8
      READ_TIMEOUT = 15
      MAX_BODY = 512 * 1024
      USER_AGENT = "Mozilla/5.0 (compatible; LuminCMS-SiteAudit/1.0)"

      # `follow:` redirects to chase. 0 returns the first answer as-is — how
      # the www/non-www check reads a 301 instead of arriving at the page.
      def self.get(url, follow: 3)
        redirects = []
        current = url.to_s
        loop do
          result = once(current)
          return result.tap { |r| r.redirects = redirects } unless result.redirect? && result.location && redirects.length < follow

          redirects << current
          current = URI.join(current, result.location).to_s
        end
      end

      def self.once(url)
        uri = URI.parse(url)
        return Result.new(url: url, error: "not an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          request = Net::HTTP::Get.new(uri.request_uri.presence || "/")
          request["User-Agent"] = USER_AGENT
          request["Accept"] = "text/html,application/xml,text/plain,*/*"
          response = http.request(request)
          Result.new(url: url, status: response.code.to_i, body: response.body.to_s.byteslice(0, MAX_BODY),
                     headers: response.each_header.to_h)
        end
      rescue Timeout::Error, SystemCallError, OpenSSL::SSL::SSLError, SocketError, Net::HTTPBadResponse,
             Net::ProtocolError, URI::InvalidURIError, IOError => e
        Result.new(url: url, error: "#{e.class.name.demodulize}: #{e.message}".truncate(160))
      end
    end
  end
end

# frozen_string_literal: true

module Reports
  module Audit
    # The third-party tags a local business site ends up with, and how to
    # recognise each one in a rendered page: the hosts its loader comes from,
    # the global it leaves on `window`, and where its account ID sits.
    #
    # The category is the honest one for consent purposes, whatever the
    # vendor's own marketing calls it. `call_tracking` is kept apart from
    # `marketing` because the audit reads it differently — it is the thing
    # that swaps the phone number.
    module Vendors
      Vendor = Struct.new(:key, :label, :category, :src, :globals, :id, keyword_init: true)

      ALL = [
        {key: "gtm", label: "Google Tag Manager", category: "tag_manager", src: %r{googletagmanager\.com/gtm\.js}, globals: %w[google_tag_manager], id: /gtm\.js\?id=(GTM-[A-Z0-9]+)/},
        {key: "ga4", label: "Google Analytics 4", category: "analytics", src: %r{googletagmanager\.com/gtag/js\?id=G-|google-analytics\.com/g/collect}, globals: %w[gtag], id: %r{gtag/js\?id=(G-[A-Z0-9]+)}},
        {key: "google_ads", label: "Google Ads", category: "marketing", src: %r{gtag/js\?id=AW-|googleadservices\.com|googleads\.g\.doubleclick\.net}, globals: [], id: /id=(AW-\d+)/},
        {key: "meta_pixel", label: "Meta Pixel", category: "marketing", src: %r{connect\.facebook\.net/[^/]+/fbevents\.js}, globals: %w[fbq], id: /fbq\(\s*['"]init['"]\s*,\s*['"](\d+)['"]/},
        {key: "clarity", label: "Microsoft Clarity", category: "analytics", src: %r{clarity\.ms/tag/}, globals: %w[clarity], id: %r{clarity\.ms/tag/([a-z0-9]+)}},
        {key: "bing_uet", label: "Microsoft Ads (UET)", category: "marketing", src: %r{bat\.bing\.com/bat\.js}, globals: %w[uetq]},
        {key: "hotjar", label: "Hotjar", category: "analytics", src: %r{static\.hotjar\.com}, globals: %w[hj], id: %r{hotjar-(\d+)\.js}},
        {key: "linkedin", label: "LinkedIn Insight", category: "marketing", src: %r{snap\.licdn\.com}, globals: %w[lintrk _linkedin_partner_id]},
        {key: "tiktok", label: "TikTok Pixel", category: "marketing", src: %r{analytics\.tiktok\.com}, globals: %w[ttq], id: /sdkid=([A-Z0-9]+)/},
        {key: "pinterest", label: "Pinterest Tag", category: "marketing", src: %r{s\.pinimg\.com/ct/}, globals: %w[pintrk]},
        {key: "plausible", label: "Plausible", category: "analytics", src: %r{plausible\.io/js/}, globals: %w[plausible]},
        {key: "fathom", label: "Fathom", category: "analytics", src: %r{cdn\.usefathom\.com}, globals: %w[fathom]},
        {key: "hubspot", label: "HubSpot", category: "marketing", src: %r{js\.hs-scripts\.com|js\.hsforms\.net|js\.hs-analytics\.net}, globals: %w[_hsq]},
        {key: "callrail", label: "CallRail", category: "call_tracking", src: %r{cdn\.callrail\.com|calltrk\.com}, globals: %w[CallTrk]},
        {key: "ctm", label: "CallTrackingMetrics", category: "call_tracking", src: %r{tctm\.co|calltrackingmetrics\.com}, globals: %w[__ctm]},
        {key: "whatconverts", label: "WhatConverts", category: "call_tracking", src: %r{whatconverts\.com}, globals: []},
        {key: "marchex", label: "Marchex", category: "call_tracking", src: %r{marchex\.io|voicestar\.com}, globals: []},
        {key: "invoca", label: "Invoca", category: "call_tracking", src: %r{invoca\.net|invocacdn\.com}, globals: %w[Invoca]},
        {key: "callsource", label: "CallSource", category: "call_tracking", src: %r{callsource\.com}, globals: []},
        {key: "intercom", label: "Intercom", category: "functional", src: %r{widget\.intercom\.io}, globals: %w[Intercom]},
        {key: "tawk", label: "tawk.to", category: "functional", src: %r{embed\.tawk\.to}, globals: %w[Tawk_API]},
        {key: "crisp", label: "Crisp", category: "functional", src: %r{client\.crisp\.chat}, globals: %w[$crisp]},
        {key: "podium", label: "Podium", category: "functional", src: %r{connect\.podium\.com}, globals: []},
        {key: "birdeye", label: "Birdeye", category: "functional", src: %r{birdeye\.com}, globals: []},
        {key: "recaptcha", label: "reCAPTCHA", category: "necessary", src: %r{google\.com/recaptcha|gstatic\.com/recaptcha}, globals: %w[grecaptcha]},
        {key: "turnstile", label: "Cloudflare Turnstile", category: "necessary", src: %r{challenges\.cloudflare\.com/turnstile}, globals: %w[turnstile]}
      ].map { |h| Vendor.new(**{globals: [], id: nil}.merge(h)).freeze }.freeze

      BY_KEY = ALL.index_by(&:key).freeze

      # The ones a consent banner exists for. A tag manager is a container —
      # whatever it holds is what matters — and necessary tags don't wait.
      CONSENT_CATEGORIES = %w[analytics marketing call_tracking functional].freeze

      # Cookies that only a tracking tag sets. Their presence on a first,
      # unconsented visit is the leak the banner was meant to stop.
      TRACKING_COOKIES = /\A(_ga|_gid|_gat|_gcl_au|_gcl_aw|_fbp|_fbc|_clck|_clsk|_hj|_uetsid|_uetvid|_ttp|_tt_enable_cookie|li_|hubspotutk|__hstc|__hssc|_pin_unauth)/

      # What is running on a rendered page, from the probe's three views of
      # it: external script URLs, the first few hundred characters of every
      # inline snippet, and which globals exist. Any one of them is enough.
      #
      # Returns [{key, label, category, ids, via}] — `via` says which of the
      # three gave it away, so the report can show its evidence.
      def self.detect(scripts: [], inline: [], globals: {})
        sources = Array(scripts).map(&:to_s)
        snippets = Array(inline).map(&:to_s)
        present = (globals || {}).select { |_, v| v }.keys.map(&:to_s)

        ALL.filter_map do |vendor|
          via = []
          via << "script" if sources.any? { |s| vendor.src.match?(s) }
          via << "inline" if snippets.any? { |s| vendor.src.match?(s) }
          via << "global" if (vendor.globals & present).any?
          next if via.empty?

          ids = (sources + snippets).filter_map { |s| vendor.id && s[vendor.id, 1] }.uniq.first(3)
          {key: vendor.key, label: vendor.label, category: vendor.category, ids: ids, via: via}
        end
      end

      # Which vendor a CMS Script installs, read from its own URL and code.
      # Nil for a snippet nobody here recognises — a custom widget, say.
      def self.for_script(script)
        haystack = [script.src, script.code].compact.join("\n")
        return nil if haystack.blank?

        ALL.find { |v| v.src.match?(haystack) || v.globals.any? { |g| haystack.include?("#{g}(") || haystack.include?("window.#{g}") } }&.key
      end

      def self.label(key) = BY_KEY[key]&.label || key.to_s

      def self.tracking_cookies(names) = Array(names).map(&:to_s).grep(TRACKING_COOKIES).uniq
    end
  end
end

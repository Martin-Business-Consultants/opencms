# frozen_string_literal: true

module Reports
  module Audit
    # Are the tags on the live site the tags the CMS says there should be,
    # and does the consent banner actually stand in front of them?
    #
    # DataForSEO renders the page as a first-time visitor who has clicked
    # nothing, so what it sees running is what runs BEFORE consent. On an
    # opt-in site that should be the necessary scripts and nothing else.
    class Tracking
      def initialize(context, findings)
        @ctx = context
        @out = findings
      end

      # How the audit answers "is this script on the site", per status:
      #
      #   on_site        the embed served it and the runtime injected it once told to accept
      #   hardcoded      not served through the CMS, but the vendor is on the page anyway
      #   not_served     the embed the site loaded doesn't list it
      #   not_injected   served, but the runtime didn't inject it after accepting
      #   category_off   filed under a category the banner doesn't offer
      #   embed_missing  the embed isn't on the site, so nothing from Scripts can be
      #   banner_off     consent is switched off in the CMS, so nothing from Scripts is served
      #   inactive       switched off in Scripts
      #   unknown        no page rendered
      STATUS_LABELS = {
        "on_site" => "On the site", "hardcoded" => "On the site (not via Scripts)", "not_served" => "Not on the site",
        "not_injected" => "Served but not loaded", "category_off" => "Blocked by consent settings",
        "embed_missing" => "Can't tell — embed missing", "banner_off" => "Not served — banner off",
        "inactive" => "Inactive", "unknown" => "Not checked"
      }.freeze

      # What the tracking checks read when no plugin manages consent: a
      # banner that's off and offers nothing.
      NO_CONSENT = Struct.new(:enabled?, :mode, :enabled_categories, :banner).new(false, "off", [], {}).freeze

      def call
        consent = @ctx.consent || NO_CONSENT
        # No rendered page, no view of what ran. Nothing to say — the render
        # failure is the finding, and Search files it.
        if @ctx.rendered.empty?
          return {checked: false, consent: {enabled: consent.enabled?, mode: consent.mode}, detected: [], cookies_before_consent: [],
                  embed: nil, managed: @ctx.scripts.map { |s| script_row(s, detected: [], embed_ids: nil, injected: nil, status: "unknown") }}
        end

        detected = detect_all
        home = @ctx.probe(@ctx.home)
        embed_present = home["banner"] || home.dig("globals", "luminConsent") == true
        cookies = Vendors.tracking_cookies(@ctx.rendered.flat_map { |p| @ctx.probe(p)["cookies"] })
        managed = script_rows(detected)

        # The consent and script checks point at settings only the plugin that
        # manages consent has; without it, only tags added by hand are news.
        consent_findings(consent, embed_present, detected, cookies) if @ctx.consent
        unmanaged_findings(consent, detected, managed)
        script_findings(consent, managed) if @ctx.consent

        embeds = @ctx.rendered.filter_map { |p| @ctx.probe(p)["embed"] }
        {
          checked: true,
          consent: {enabled: consent.enabled?, mode: consent.mode, embed_present: embed_present, banner_shown: home["banner"]},
          embed: embeds.any? ? {version: embeds.first["version"], script_ids: embeds.flat_map { |e| e["ids"] }.uniq} : nil,
          detected: detected.map { |v| v.merge(managed: managed.any? { |m| m[:vendor] == v[:key] }) },
          managed: managed,
          cookies_before_consent: cookies
        }
      end

      private

      # One row per vendor across every rendered page, with the pages it
      # appeared on — a pixel on the contact page only is still a pixel.
      def detect_all
        rows = {}
        @ctx.rendered.each do |page|
          probe = @ctx.probe(page)
          Vendors.detect(scripts: probe["scripts"], inline: probe["inline"], globals: probe["globals"]).each do |v|
            row = rows[v[:key]] ||= v.merge(pages: [], ids: [])
            row[:pages] |= [page[:url]]
            row[:ids] |= v[:ids]
            row[:via] |= v[:via]
          end
        end
        rows.values.sort_by { |v| [v[:category], v[:label]] }
      end

      def gated?(vendor) = Vendors::CONSENT_CATEGORIES.include?(vendor[:category])

      def consent_findings(consent, embed_present, detected, cookies)
        gated = detected.select { |v| gated?(v) }

        unless consent.enabled?
          if gated.any?
            @out.add(key: "consent:off", area: "consent", severity: "medium",
                     title: "#{gated.length} tracking tag#{"s" unless gated.length == 1} run with no consent banner",
                     body: "#{gated.map { |v| v[:label] }.to_sentence} load for every visitor. The banner is switched off in Settings → Consent; " \
                           "switch it on and move these tags into Scripts so a visitor gets a say. (Opt-out is available where the law allows it.)",
                     fix: {label: "Consent settings", href: "/settings/consent"},
                     evidence: {vendors: gated.map { |v| v[:key] }})
          else
            @out.pass(key: "consent:none-needed", area: "consent", title: "No tracking tags found — nothing for a banner to gate yet")
          end
          return
        end

        unless embed_present
          @out.add(key: "consent:embed-missing", area: "consent", severity: "critical",
                   title: "Consent banner is switched on but isn't on the live site",
                   body: "The CMS is set to ask visitors, but the embed isn't in the site's <head>, so nothing asks and nothing is gated. " \
                         "Add the one-line script tag from Settings → Consent to the site's layout.",
                   fix: {label: "Get the embed", href: "/settings/consent"})
          return
        end

        @out.pass(key: "consent:embed", area: "consent", title: "Consent banner is live on the site")

        if consent.mode == "opt_in"
          # A vendor the CMS files under "necessary" is meant to run before
          # consent — call tracking on a US site, say. That is the operator's
          # call, made in Scripts, and the audit respects it.
          necessary_now = @ctx.scripts.select { |s| s.active && s.necessary? }.filter_map { |s| Vendors.for_script(s) }
          early = gated.reject { |v| v[:category] == "necessary" || necessary_now.include?(v[:key]) }
          if early.any?
            early.each do |v|
              in_cms = @ctx.scripts.any? { |s| Vendors.for_script(s) == v[:key] }
              @out.add(key: "tracking:early:#{v[:key]}", area: "tracking", severity: "high",
                       title: "#{v[:label]} loads before the visitor has consented",
                       body: in_cms ? "It's managed in Scripts, so the banner would gate it — but a second copy is hard-coded in the site and runs on every visit. Remove the copy from the site's code." :
                                      "It isn't in Scripts, so the banner can't hold it back. Remove it from the site's code and add it under Tools → Scripts in the right category.",
                       fix: {label: "Scripts", href: "/scripts"},
                       evidence: {vendor: v[:key], ids: v[:ids], pages: v[:pages], via: v[:via]})
            end
          else
            @out.pass(key: "consent:gated", area: "consent", title: "No tracking tag runs before consent")
          end

          if cookies.any?
            @out.add(key: "tracking:cookies", area: "tracking", severity: "high",
                     title: "Tracking cookies are set before consent",
                     body: "A first visit with no choice made already carries #{cookies.first(5).join(", ")}. Whatever sets them is running ahead of the banner.",
                     fix: {label: "Scripts", href: "/scripts"}, evidence: {cookies: cookies})
          else
            @out.pass(key: "consent:cookies", area: "consent", title: "No tracking cookies before consent")
          end
        end

        return if consent.banner["policy_url"].present?

        @out.add(key: "consent:policy", area: "consent", severity: "low",
                 title: "The banner has no privacy policy link",
                 body: "Visitors are asked to agree to something they can't read. Add the policy URL.",
                 fix: {label: "Consent settings", href: "/settings/consent"})
      end

      def unmanaged_findings(consent, detected, managed)
        managed_keys = managed.map { |m| m[:vendor] }.compact
        stray = detected.select { |v| (gated?(v) || v[:category] == "tag_manager") && !managed_keys.include?(v[:key]) }

        if stray.empty?
          @out.pass(key: "tracking:managed", area: "tracking", title: "Every tag on the site is managed in Scripts") if detected.any?
          return
        end

        stray.each do |v|
          container = v[:category] == "tag_manager"
          @out.add(key: "tracking:unmanaged:#{v[:key]}", area: "tracking",
                   severity: container ? "medium" : (consent.enabled? ? "medium" : "low"),
                   title: "#{v[:label]} is on the site but not in Scripts",
                   body: container ? "A tag container can inject anything, and none of it is gated by consent or visible here. Add it under Scripts so the banner controls when it loads, and audit what's inside it." :
                                     "It was added to the site by hand#{v[:ids].any? ? " (#{v[:ids].join(", ")})" : ""}. Add it under Tools → Scripts as #{v[:category].tr("_", " ")} so consent gates it and it shows up in this list.",
                   fix: {label: "Add to Scripts", href: "/scripts"},
                   evidence: {vendor: v[:key], ids: v[:ids], pages: v[:pages]})
        end
      end

      # One row per CMS script with the evidence and the verdict. The embed's
      # own script list says what the site was handed; the injections after
      # `acceptAll` say what the runtime actually put on the page.
      def script_rows(detected)
        embeds = @ctx.rendered.filter_map { |p| @ctx.probe(p)["embed"] }
        embed_ids = embeds.any? ? embeds.flat_map { |e| e["ids"] }.uniq : nil
        injections = @ctx.rendered.filter_map { |p| @ctx.probe(p)["injected"] }
        injected = injections.any? ? injections.flatten.uniq : nil
        consent = @ctx.consent || NO_CONSENT
        offered = consent.enabled_categories + ["necessary"]

        @ctx.scripts.map do |script|
          vendor = Vendors.for_script(script)
          seen = vendor && detected.any? { |v| v[:key] == vendor }
          served = embed_ids&.include?(script.id) || false
          put = injected&.include?(script.id) || false
          status =
            if !script.active then "inactive"
            elsif !consent.enabled? then seen ? "hardcoded" : "banner_off"
            elsif embed_ids.nil? then seen ? "hardcoded" : "embed_missing"
            elsif !offered.include?(script.category) then "category_off"
            elsif served && put then "on_site"
            elsif served then "not_injected"
            elsif seen then "hardcoded"
            else "not_served"
            end
          script_row(script, detected: seen, embed_ids: embed_ids, injected: injected, status: status, vendor: vendor)
        end
      end

      def script_row(script, detected:, embed_ids:, injected:, status:, vendor: Vendors.for_script(script))
        {
          id: script.id, name: script.name, category: script.category, vendor: vendor, active: script.active,
          detected: detected ? true : false,
          served: embed_ids&.include?(script.id) || false,
          injected: injected&.include?(script.id) || false,
          status: status, status_label: STATUS_LABELS.fetch(status)
        }
      end

      def script_findings(consent, managed)
        active = managed.select { |m| m[:active] }

        off = active.select { |m| m[:status] == "banner_off" }
        if off.any?
          @out.add(key: "tracking:banner-off", area: "tracking", severity: "medium",
                   title: "#{off.length} script#{"s" unless off.length == 1} in the CMS #{off.length == 1 ? "isn't" : "aren't"} on the site — the consent banner is off",
                   body: "Scripts reach the site only through the banner's embed, and the banner is switched off in Settings → Consent. #{off.map { |m| m[:name] }.to_sentence} #{off.length == 1 ? "is" : "are"} waiting behind it.",
                   fix: {label: "Consent settings", href: "/settings/consent"}, evidence: {scripts: off.map { |m| m[:id] }})
        end

        active.each do |m|
          case m[:status]
          when "on_site"
            @out.pass(key: "tracking:script:#{m[:id]}", area: "tracking", title: "#{m[:name]} is on the site")
          when "hardcoded"
            @out.pass(key: "tracking:script:#{m[:id]}", area: "tracking", title: "#{m[:name]} is on the site (hard-coded, not through Scripts)")
          when "not_served"
            @out.add(key: "tracking:script:#{m[:id]}", area: "tracking", severity: "high",
                     title: "#{m[:name]} isn't on the site",
                     body: "The embed the site loaded doesn't include it. The site caches /consent.js for up to five minutes, so if this was just added, run the audit again. " \
                           "If it persists, the site is loading the embed from a different CMS, or a cached copy of it.",
                     fix: {label: "Scripts", href: "/scripts"}, evidence: {script_id: m[:id], vendor: m[:vendor]})
          when "not_injected"
            @out.add(key: "tracking:script:#{m[:id]}", area: "tracking", severity: "medium",
                     title: "#{m[:name]} is served to the site but the banner didn't load it after consent",
                     body: "The runtime injected the other scripts and skipped this one. Check that the code is plain JavaScript with no <script> tags, and that the category matches one the banner offers.",
                     fix: {label: "Edit in Scripts", href: "/scripts"}, evidence: {script_id: m[:id]})
          when "category_off"
            @out.add(key: "tracking:script:#{m[:id]}", area: "tracking", severity: "medium",
                     title: "#{m[:name]} never loads — its category (#{m[:category]}) is switched off in the consent settings",
                     body: "A category the banner doesn't offer can't be granted, so scripts filed under it are never injected. Offer the category, or refile the script.",
                     fix: {label: "Consent settings", href: "/settings/consent"}, evidence: {script_id: m[:id], category: m[:category]})
          end
        end
      end
    end
  end
end

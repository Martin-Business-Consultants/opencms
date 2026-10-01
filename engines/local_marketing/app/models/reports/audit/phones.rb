# frozen_string_literal: true

module Reports
  module Audit
    # The phone number: is it there, is it tappable, is it the business's,
    # and if call tracking is installed does it actually swap.
    #
    # Two renders of the home page. The first is an ordinary visit; the
    # second carries a Google Ads click (`gclid`) in the URL, which is the
    # visit dynamic number insertion exists for. Same number both times with
    # a tracking vendor on the page means the swap isn't firing.
    class Phones
      def initialize(context, findings)
        @ctx = context
        @out = findings
      end

      def call
        # The phone checks read the home page; without its render they would
        # report a number missing from a page nobody saw.
        return {checked: false, business: nil, organic: [], paid: [], tel: [], vendors: [], swap_observed: false, paid_checked: false} if @ctx.home.nil? || @ctx.home[:probe].nil?

        business = digits(@ctx.profile.phone)
        home = @ctx.probe(@ctx.home)
        paid = @ctx.probe(@ctx.paid)
        organic = numbers(home)
        paid_numbers = numbers(paid)
        tel = home["tel"].map { |t| digits(t) }.reject(&:empty?).uniq
        vendors = detected_call_tracking
        swap = @ctx.paid.present? && paid_numbers.any? && paid_numbers != organic

        if business.empty?
          @out.add(key: "calls:no-business-phone", area: "calls", severity: "low",
                   title: "No business phone in Settings → Reporting, so the site's number can't be checked",
                   body: "Add the number the business answers, and the audit will compare it to what the site shows and to Google.",
                   fix: {label: "Reporting settings", href: "/settings/reporting"})
        end

        if organic.empty? && home["phones"].empty?
          @out.add(key: "calls:none", area: "calls", severity: "high",
                   title: "No phone number on the home page",
                   body: "A local business site with no visible number loses the visitors who'd rather call. Put it in the header and the footer, as a tap-to-call link.",
                   fix: {label: "In the site's code"})
        else
          @out.pass(key: "calls:present", area: "calls", title: "Phone number is on the home page")
          if tel.empty?
            @out.add(key: "calls:not-tappable", area: "calls", severity: "medium",
                     title: "The phone number isn't a tap-to-call link",
                     body: "On a phone, text isn't dialable. Wrap the number in an <a href=\"tel:…\"> — most calls to a local business start on a mobile screen.",
                     fix: {label: "In the site's code"}, evidence: {shown: home["phones"].first(3)})
          else
            @out.pass(key: "calls:tappable", area: "calls", title: "Phone number is tap-to-call")
            mismatched = tel.reject { |t| organic.include?(t) }
            if mismatched.any? && organic.any?
              @out.add(key: "calls:tel-mismatch", area: "calls", severity: "low",
                       title: "A tap-to-call link dials a different number than it shows",
                       body: "Displayed #{format_all(organic)}; the link dials #{format_all(mismatched)}. Usually a stale tel: attribute.",
                       fix: {label: "In the site's code"})
            end
          end
        end

        if vendors.any?
          if swap
            @out.pass(key: "calls:dni", area: "calls", title: "Call tracking swaps the number for paid visits",
                      evidence: {vendor: vendors.first, organic: format_all(organic), paid: format_all(paid_numbers)})
          elsif @ctx.paid.present?
            @out.add(key: "calls:dni-static", area: "calls", severity: "medium",
                     title: "#{Vendors.label(vendors.first)} is installed but the number never changes",
                     body: "A visit from a Google Ads click showed the same number as an ordinary visit. Either the swap targets don't match the number on the page, the pool is exhausted, or the script loads after the number renders.",
                     fix: {label: "In the site's code"}, evidence: {organic: format_all(organic), paid: format_all(paid_numbers)})
          end
        elsif business.present? && organic.any? && !organic.include?(business)
          @out.add(key: "calls:wrong-number", area: "calls", severity: "high",
                   title: "The phone number on the site isn't the business number",
                   body: "The site shows #{format_all(organic)}; Settings → Reporting says #{format(business)}. With no call tracking on the page, that's a mismatch Google sees too — the listing, the site and the directories should all agree.",
                   fix: {label: "Check the number", href: "/settings/reporting"}, evidence: {site: format_all(organic), business: format(business)})
        elsif business.present? && organic.include?(business)
          @out.pass(key: "calls:matches", area: "calls", title: "The site shows the business number")
        end

        {
          business: business.presence && format(business),
          organic: organic.map { |n| format(n) },
          paid: paid_numbers.map { |n| format(n) },
          tel: tel.map { |n| format(n) },
          vendors: vendors,
          swap_observed: swap,
          paid_checked: @ctx.paid.present?
        }
      end

      private

      def detected_call_tracking
        @ctx.rendered.flat_map do |page|
          probe = @ctx.probe(page)
          Vendors.detect(scripts: probe["scripts"], inline: probe["inline"], globals: probe["globals"])
                 .select { |v| v[:category] == "call_tracking" }.map { |v| v[:key] }
        end.uniq
      end

      def numbers(probe)
        (probe["phones"] + probe["tel"]).map { |p| digits(p) }.select { |d| d.length == 10 }.uniq
      end

      # US numbers: the last ten digits, so +1 and 1- prefixes compare equal.
      def digits(value)
        d = value.to_s.gsub(/\D/, "")
        d.length > 10 ? d[-10..] : d
      end

      def format(d)
        return d unless d.length == 10

        "(#{d[0, 3]}) #{d[3, 3]}-#{d[6, 4]}"
      end

      def format_all(list) = list.map { |d| format(d) }.to_sentence
    end
  end
end

# frozen_string_literal: true

module Reports
  module Audit
    # Do the forms work — end to end, from the field on the page to the
    # inbox someone reads?
    #
    # The CMS owns the forms, so this is a real comparison rather than a
    # guess: the definition says which fields are required and where the
    # form posts; the rendered page says what's actually there; the email
    # template says who hears about a submission. What can't be tested
    # without emailing a client is left alone — the audit never submits a
    # live form. It validates a synthetic submission against the definition
    # instead, which is the same code the real endpoint runs.
    class Forms
      SEARCH_FORM = ->(f) { f["method"].to_s == "get" || Array(f["fields"]).length <= 1 }

      def initialize(context, findings)
        @ctx = context
        @out = findings
      end

      def call
        rendered = rendered_forms
        rows = @ctx.forms.map { |form| check(form, rendered) }
        strays = rendered.reject { |r| r[:matched] || SEARCH_FORM.call(r) }
        strays.each do |r|
          @out.add(key: "forms:stray:#{Digest::SHA1.hexdigest("#{r[:page]}#{r["action"]}")[0, 6]}", area: "forms", severity: "low",
                   title: "A form on #{short(r[:page])} isn't one of the CMS forms",
                   body: "It posts to #{r["action"].presence || "the same page"}, so its submissions won't appear in Forms → Submissions or send the CMS's notifications. If it should, build it as a CMS form.",
                   fix: {label: "Forms", href: "/forms"}, evidence: {page: r[:page], action: r["action"], fields: r["fields"].map { |f| f["name"] }})
        end

        cors_finding

        {forms: rows, unknown_forms: strays.map { |r| {page: r[:page], action: r["action"], fields: r["fields"].map { |f| f["name"] }} }}
      end

      private

      def rendered_forms
        @ctx.rendered.flat_map do |page|
          @ctx.probe(page)["forms"].map { |f| f.merge(page: page[:url], "fields" => Array(f["fields"]).select { |x| x.is_a?(Hash) }) }
        end
      end

      def check(form, rendered)
        slug = form.slug
        mine = rendered.select { |r| r["action"].to_s.include?("/api/forms/#{slug}/submissions") }
        mine = rendered.select { |r| field_overlap(form, r) >= 0.6 && !r[:matched] } if mine.empty?
        mine.each { |r| r[:matched] = true }

        defined = Array(form.fields).map { |f| f["name"].to_s }
        required = Array(form.fields).select { |f| f["required"] }.map { |f| f["name"].to_s }
        rendered_names = mine.flat_map { |r| r["fields"].map { |f| f["name"].to_s } }.uniq
        missing_required = mine.any? ? required - rendered_names : []
        honeypot = mine.any? && rendered_names.include?(form.class::HONEYPOT_FIELD)
        posts_to_cms = mine.any? && mine.all? { |r| r["action"].to_s.include?("/api/forms/") }

        notify = form.notification_email
        recipients = notify&.recipient_list || []
        dry_run = form.validate_submission(sample_data(form), {})
        last = form.submissions.maximum(:created_at)

        fix = {label: "Edit form", href: "/forms/#{slug}/edit"}
        emails_fix = {label: "Notification email", href: "/forms/#{slug}/emails/notification/edit"}

        if mine.empty? && @ctx.rendered.any?
          @out.add(key: "forms:absent:#{slug}", area: "forms", severity: "medium",
                   title: "“#{form.title}” isn't on any audited page",
                   body: "Checked #{@ctx.rendered.length} page#{"s" unless @ctx.rendered.length == 1}. If it lives on a page that wasn't audited, add that page to the audit URLs; if it should be on the site and isn't, that's a build to fix.",
                   fix: {label: "Audit URLs", href: "/settings/reporting"}, evidence: {pages_checked: @ctx.rendered.map { |p| p[:url] }})
        elsif mine.any?
          if missing_required.any?
            @out.add(key: "forms:fields:#{slug}", area: "forms", severity: "high",
                     title: "“#{form.title}” on the site is missing required field#{"s" unless missing_required.length == 1}: #{missing_required.join(", ")}",
                     body: "The CMS requires #{missing_required.to_sentence}, and the rendered form has no such input — every submission from the site will be rejected. Rebuild the form on the site from the current definition.",
                     fix: fix, evidence: {required: required, rendered: rendered_names})
          end
          unless posts_to_cms
            @out.add(key: "forms:action:#{slug}", area: "forms", severity: "medium",
                     title: "“#{form.title}” posts somewhere other than the CMS",
                     body: "The rendered form's action is #{mine.map { |r| r["action"].presence || "(same page)" }.uniq.to_sentence}. Submissions won't land in the inbox or trigger notifications until it posts to /api/forms/#{slug}/submissions.",
                     fix: fix, evidence: {actions: mine.map { |r| r["action"] }})
          end
          unless honeypot
            @out.add(key: "forms:honeypot:#{slug}", area: "forms", severity: "medium",
                     title: "“#{form.title}” has no spam trap",
                     body: "The hidden #{form.class::HONEYPOT_FIELD} field isn't in the rendered form, so bots aren't filtered before they hit the inbox. Add it as a visually hidden input.",
                     fix: {label: "In the site's code"})
          end
        end

        if notify.nil? || !notify.enabled? || recipients.empty?
          @out.add(key: "forms:notify:#{slug}", area: "forms", severity: "high",
                   title: "Nobody is emailed when “#{form.title}” is submitted",
                   body: "Submissions land in the inbox here, but no notification goes out. A lead that waits until someone remembers to look is a lead that called the next business.",
                   fix: emails_fix)
        end

        if dry_run.any?
          @out.add(key: "forms:dryrun:#{slug}", area: "forms", severity: "high",
                   title: "“#{form.title}” rejects a well-formed submission",
                   body: "Validating a filled-in copy against the definition failed: #{dry_run.map { |k, v| "#{k} #{Array(v).join(", ")}" }.first(3).join("; ")}. Real submissions will fail the same way.",
                   fix: fix, evidence: {errors: dry_run})
        end

        if form.status == "published" && last.nil? && form.created_at < 30.days.ago && mine.any?
          @out.add(key: "forms:silent:#{slug}", area: "forms", severity: "low",
                   title: "“#{form.title}” has never received a submission",
                   body: "Published #{form.created_at.to_date}, on the site, and not one submission. Worth a test from a phone.",
                   fix: {label: "Submissions", href: "/forms/#{slug}/submissions"})
        end

        healthy = mine.any? && missing_required.empty? && posts_to_cms && honeypot && recipients.any? && dry_run.empty?
        @out.pass(key: "forms:ok:#{slug}", area: "forms", title: "“#{form.title}” is wired: on the site, spam-trapped, notifications on") if healthy

        {
          slug: slug, title: form.title, status: form.status,
          rendered_on: mine.map { |r| r[:page] }.uniq,
          posts_to_cms: posts_to_cms, honeypot: honeypot,
          missing_required: missing_required, defined_fields: defined, rendered_fields: rendered_names,
          notify: {enabled: notify&.enabled? || false, recipients: recipients.length},
          dry_run_ok: dry_run.empty?,
          submissions: form.submissions.count, last_submission_at: last&.iso8601,
          healthy: healthy
        }
      end

      def field_overlap(form, rendered)
        defined = Array(form.fields).map { |f| f["name"].to_s }
        return 0.0 if defined.empty?

        names = rendered["fields"].map { |f| f["name"].to_s }
        (defined & names).length / defined.length.to_f
      end

      # A plausible filled-in copy, per field type — what the endpoint would
      # receive from a person. Files are skipped: their check is size and
      # type, and there is no file.
      def sample_data(form)
        Array(form.fields).each_with_object({}) do |f, out|
          name = f["name"].to_s
          out[name] = case f["type"]
          when "email" then "audit@example.com"
          when "tel" then "555-555-0123"
          when "url" then "https://example.com"
          when "select", "radio" then Array(f["options"]).first&.dig("value").to_s
          when "checkbox" then "true"
          when "file" then next
          else "Automated site audit (ignore)"
          end
        end
      end

      def cors_finding
        general = Setting.get("general")
        return if general["site_base_url"].to_s.start_with?("http")

        @out.add(key: "forms:cors", area: "forms", severity: "medium",
                 title: "Site base URL isn't set, so form submissions rely on wide-open CORS",
                 body: "Without it the CMS accepts submissions from any origin. Set the public site's URL in Settings → General and the endpoint tightens to it.",
                 fix: {label: "General settings", href: "/settings/general"})
      end

      def short(url) = url.to_s.sub(%r{\Ahttps?://[^/]+}, "").presence || "/"
    end
  end
end

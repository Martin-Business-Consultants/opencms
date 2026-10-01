# frozen_string_literal: true

# What to have in place before a site goes live, checked against the site as
# it is rather than ticked by hand: the Docs module's go-live page,
# GET /api/go_live and `cms go-live` all read it. Each check says whether
# it passes (`ok`: true, false, or nil when it doesn't apply here), what it's
# about, and where to fix it — in the admin and from the CLI.
#
# Plugins' parts come through what they provide (Cms::Plugins.provided),
# so a site without Forms or Consent & Scripts simply has fewer checks.
module GoLiveChecklist
  Check = Checklist::Check

  GROUPS = ["The site", "Content", "Forms", "Trust & privacy", "Safety"].freeze

  module_function

  def checks
    (site + content + forms + trust + safety).compact
  end

  def summary(list = checks) = Checklist.summary(list)

  def site
    general = Setting.get("general")
    deploy = Setting.get(Deploys::SETTING_KEY)
    build = Frontend.last_build
    [
      Check.new(key: "site_base_url", group: "The site", title: "The site's address is set",
        detail: "Settings › General › Site base URL: the public origin (https://…). Sitemap URLs, form CORS and preview links are built from it.",
        ok: general["site_base_url"].to_s.start_with?("https://"), href: "/settings/general", cli: "cms get /settings/general"),
      Check.new(key: "frontend_connected", group: "The site", title: "The Astro site builds from the CMS",
        detail: build ? "Its last build reported #{build[:built_at]&.to_date}." : "Run the installer in the site's project, then build it once: it reports each build here.",
        ok: build.present?, href: "/developers", cli: "cms frontend"),
      Check.new(key: "service_token", group: "The site", title: "The site reads with a service token of its own",
        detail: "A read-only token on the Production site role, not a person's: it doesn't change when their role or token does.",
        ok: ServiceToken.active.where.not(last_used_at: nil).exists?, href: "/settings/service_tokens", cli: "cms service-tokens"),
      Check.new(key: "rebuilds", group: "The site", title: "Publishing rebuilds the site",
        detail: "Settings › Deploy: a GitHub dispatch or a host's build hook, so a published change goes live without anyone deploying.",
        ok: Deploys.current.configured?, href: "/settings/deploy", cli: "cms deploy"),
      Check.new(key: "last_deploy", group: "The site", title: "The last rebuild succeeded",
        detail: deploy["last_status"].present? ? "It was #{deploy["last_status"]}." : "No rebuild has run yet: Deploy now, or publish something.",
        ok: Deploys.current.configured? ? deploy["last_status"] == "success" : nil, href: "/settings/deploy", cli: "cms deploy now")
    ]
  end

  def content
    home = Page.find_by(path: "home")
    published = Page.where(status: "published")
    untitled = published.to_a.count { |page| page.seo.to_h["meta_description"].blank? }
    images = Asset.images.to_a
    unlabelled = images.count { it.alt.blank? && it.referencing_records.any? }
    [
      Check.new(key: "home_page", group: "Content", title: "There's a published home page",
        detail: "A page at the path home, published: the site serves it at /.",
        ok: home&.status == "published", href: "/pages", cli: "cms page home"),
      Check.new(key: "meta_descriptions", group: "Content", title: "Published pages have meta descriptions",
        detail: untitled.zero? ? "Every published page has one." : "#{untitled} published #{"page".pluralize(untitled)} #{untitled == 1 ? "has" : "have"} none (a page's SEO box). Search results show it under the title.",
        ok: published.any? ? untitled.zero? : nil, href: "/pages?status=published", cli: "cms pages --status published"),
      Check.new(key: "alt_text", group: "Content", title: "Images the site uses have alt text",
        detail: unlabelled.zero? ? "Every image in use has alt text." : "#{unlabelled} #{"image".pluralize(unlabelled)} in use #{unlabelled == 1 ? "has" : "have"} none. Screen readers read it; search engines index it.",
        ok: images.any? ? unlabelled.zero? : nil, href: "/file_manager?kind=images", cli: "cms asset <id> set alt=\"…\""),
      Check.new(key: "redirects", group: "Content", title: "Old addresses redirect",
        detail: "Replacing a site? Import its old URLs (Tools › Redirects › Import CSV) so links and search rankings follow.",
        ok: nil, href: "/tools/redirects", cli: "cms redirects")
    ]
  end

  def forms
    published = Cms::Plugins.provided(:published_forms)
    return [] if published.nil?

    silent = Array(published).reject { |form| form.notification_email&.enabled && form.notification_email.recipient_list.any? }
    [
      Check.new(key: "form_notifications", group: "Forms", title: "Every live form tells someone when it's used",
        detail: silent.empty? ? "Each published form's notification email is on, with recipients." : "#{silent.map(&:title).to_sentence} #{silent.one? ? "has" : "have"} no notification email switched on with recipients.",
        ok: Array(published).any? ? silent.empty? : nil, href: "/forms", cli: "cms emails <form>"),
      Check.new(key: "form_sender", group: "Forms", title: "Form emails come from your domain",
        detail: "Settings › Forms › From address: mail from an address on a domain you own gets delivered; the default may not.",
        ok: Setting.get("forms_settings")["from_email"].present?, href: "/settings/forms", cli: nil)
    ]
  end

  def trust
    branding = Setting.get("branding")
    checks = [
      Check.new(key: "favicon", group: "Trust & privacy", title: "The site has a logo and favicon",
        detail: "Settings › Branding: the logo heads form emails; the favicon marks the browser tab.",
        ok: branding["logo_id"].present? && branding["favicon_id"].present?, href: "/settings/branding", cli: nil)
    ]
    scripts = Cms::Plugins.provided(:scripts)
    consent = Cms::Plugins.provided(:consent_config)
    if scripts && consent
      tracking = Array(scripts).select { it.active && !it.necessary? }
      checks << Check.new(key: "consent", group: "Trust & privacy", title: "Tracking waits for consent",
        detail: tracking.any? ? "#{tracking.size} active #{"script".pluralize(tracking.size)} beyond the necessary: the consent banner must be on, and the layout must load /consent.js." : "No tracking scripts are set up.",
        ok: tracking.any? ? consent.enabled? == true : nil, href: "/settings/consent", cli: nil)
    end
    checks
  end

  def safety
    admins = User.joins(:role).where(roles: {name: "Admin"})
    [
      Check.new(key: "two_factor", group: "Safety", title: "Admins use two-factor sign-in",
        detail: "Settings › Two-factor, for each person with the Admin role.",
        ok: admins.any? ? admins.where(totp_enabled: false).none? : nil, href: "/settings/two_factor", cli: nil),
      Check.new(key: "backup", group: "Safety", title: "There's a backup",
        detail: "Tools › Backup: download one before launch; updates take their own automatically.",
        ok: SiteBackup.data_archives.any?, href: "/tools/backup", cli: "cms backup > backup.tar.gz"),
      Check.new(key: "trash_purge", group: "Safety", title: "The trash empties itself",
        detail: "Tools › Schedules › Trash purge: deleted content goes for good after its retention window.",
        ok: RecurringTask.where(recipe_key: "trash_purge", enabled: true).exists?, href: "/tools/recurring_tasks", cli: "cms schedule trash_purge --on")
    ]
  end
end

# frozen_string_literal: true

# Computes the "Get started" checklist surfaced on the dashboard.
# Each step is a small immutable record: a key, a label, a longer hint, the
# URL of the page that completes it, and a boolean `done` derived from
# site state.
#
# Dismissal is sticky: once the user explicitly hides the checklist (or
# once everything is done and they've acknowledged), the Setting flips and
# the dashboard stops rendering it. Re-show is a manual editor action via
# the kebab menu on the dashboard (out of scope for v1 — just edit the
# Setting via console if needed).
module OnboardingChecklist
  SETTING_KEY = "onboarding"

  Step = Struct.new(:key, :title, :hint, :href, :cta, :done, keyword_init: true) do
    def as_json(*)
      {
        "key"   => key,
        "title" => title,
        "hint"  => hint,
        "href"  => href,
        "cta"   => cta,
        "done"  => done
      }
    end
  end

  module_function

  # Pull every signal in a single sweep so the dashboard render is one
  # round-trip's worth of DB queries.
  def steps
    general = Setting.get("general")
    deploy  = Setting.get("deploy")

    [
      Step.new(
        key:   "site_base_url",
        title: "Set your site base URL",
        hint:  "The canonical public origin of the deployed site (e.g. https://acme.com). Drives sitemap URLs, form-submission CORS, and the public preview link.",
        href:  "/settings/general",
        cta:   "Open General settings",
        done:  general["site_base_url"].to_s.start_with?("http")
      ),
      Step.new(
        key:   "connect_site",
        title: "Connect your Astro site",
        hint:  "In the site's project, run curl -fsSL <this CMS>/frontend/install.sh | sh. It adds the integration, wires cms() into astro.config and gets the site a read-only token of its own. Build it once and it reports in here.",
        href:  "/developers",
        cta:   "Open Developers",
        done:  Frontend.connected?
      ),
      Step.new(
        key:   "deploy_hook",
        title: "Rebuild the site when you publish",
        hint:  "In Settings → Deploy, choose GitHub (a repository_dispatch the site's cms-publish workflow answers) or paste your host's build-hook URL. Publishing then rebuilds the site within a minute or two.",
        href:  "/settings/deploy",
        cta:   "Open Deploy settings",
        done:  Deploys.current.configured?
      ),
      Step.new(
        key:   "first_deploy",
        title: "First successful deploy",
        hint:  "Hit \"Deploy now\" once it's set up (or publish a page) to confirm the CMS can reach your host.",
        href:  "/settings/deploy",
        cta:   "Open Deploy settings",
        done:  deploy["last_status"] == "success"
      ),
      Step.new(
        key:   "publish_page",
        title: "Publish your first page",
        hint:  "Edit the draft Home page, fill in your hero, and flip status to Published. The deploy hook fires automatically.",
        href:  "/pages",
        cta:   "Open Pages",
        done:  Page.where(status: "published").exists?
      )
    ]
  end

  def dismissed?
    Setting.get(SETTING_KEY)["dismissed"] == true
  end

  def dismiss!
    Setting.set(SETTING_KEY, {"dismissed" => true, "dismissed_at" => Time.current.iso8601})
  end

  def reopen!
    Setting.set(SETTING_KEY, {"dismissed" => false})
  end

  # Steps that don't have a discoverable backend signal (e.g. scaffolding
  # happens on the user's machine) are completed by the user clicking
  # "Mark done" on the row.
  def acknowledge!(key)
    config = Setting.get(SETTING_KEY)
    acks = Array(config["acknowledged"])
    acks << key.to_s unless acks.include?(key.to_s)
    Setting.set(SETTING_KEY, {"acknowledged" => acks.uniq})
  end

  def unacknowledge!(key)
    config = Setting.get(SETTING_KEY)
    acks = Array(config["acknowledged"]) - [key.to_s]
    Setting.set(SETTING_KEY, {"acknowledged" => acks})
  end

  def manually_acknowledged?(key)
    Array(Setting.get(SETTING_KEY)["acknowledged"]).include?(key.to_s)
  end

  # Convenience for the controller — bundle steps + meta into one
  # serializable hash.
  def payload
    list = steps
    {
      "dismissed"   => dismissed?,
      "all_done"    => list.all?(&:done),
      "done_count"  => list.count(&:done),
      "total_count" => list.size,
      "steps"       => list.map(&:as_json)
    }
  end
end

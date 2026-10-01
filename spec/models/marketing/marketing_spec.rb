# frozen_string_literal: true

require "rails_helper"

# The deterministic core of the Marketer's Report. These are the numbers a
# client is shown; they must come out the same for the same snapshots, and
# every rule in "Do next" must be traceable to a figure.
RSpec.describe "Marketing" do
  before { Report.destroy_all; Recommendation.destroy_all; Agent.destroy_all; RecurringTask.destroy_all; Setting.delete_all; Page.destroy_all }

  def snapshot(kind, data, at: Time.current)
    Report.create!(kind: kind, status: "complete", data: data, created_at: at)
  end

  let(:template) { Marketing::BusinessRegistry.find("self_storage") }
  let(:profile) { Reports::Profile.new("business_name" => "Acme", "domain" => "acme.com", "location_name" => "Austin,Texas,United States", "tracked_keywords" => "a\nb") }

  describe Marketing::BusinessRegistry do
    it "loads every shipped template cleanly, keyed by file name, with known reports, agents and targets" do
      Marketing::BusinessRegistry.reload!
      expect(Marketing::BusinessRegistry.problems).to be_empty
      expect(Marketing::BusinessRegistry.keys.length).to be >= 8
      Marketing::BusinessRegistry.all.each do |key, t|
        expect(t.key).to eq(key)
        expect(t.problems).to be_empty, "#{key}: #{t.problems.join("; ")}"
        expect(t.baseline_cost).to be > 0
      end
    end

    it "derives concrete keywords from patterns, once per service and per modifier, capped" do
      d = template.defaults_for(city: "Austin")
      expect(d[:keywords]).to include("self storage Austin", "storage units near me", "cheap self storage Austin")
      expect(d[:keywords].length).to be <= 40
      expect(d[:keywords].uniq.length).to eq(d[:keywords].length)
      expect(d[:map_keywords]).to eq(d[:keywords].first(3))
      expect(d[:directories]).to include("yelp.com", "sparefoot.com")
      expect(d[:map_grid_size]).to eq(5)
      expect(d[:targets]["map_pack_share"]).to eq(60.0)
      # A service-area trade gets the wider grid.
      expect(Marketing::BusinessRegistry.find("plumber").defaults_for(city: "Austin")[:map_grid_size]).to eq(7)
    end
  end

  describe Marketing::Targets do
    it "layers stored values over the template's over conservative fallbacks" do
      expect(Marketing::Targets.all(nil)["rating"]).to eq(4.6)
      expect(Marketing::Targets.all(template)["reviews"]).to eq(80.0)
      Marketing::Targets.save("reviews" => "200", "bogus" => "1", "rating" => "0")
      expect(Marketing::Targets.all(template)["reviews"]).to eq(200.0)
      expect(Marketing::Targets.all(template)["rating"]).to eq(4.6) # zero is "unset"
      expect(Setting.get("marketing")["targets"]).not_to have_key("bogus")
    end
  end

  describe Marketing::Scorecard do
    it "scores progress to target per metric, averages a pillar, and leaves unmeasured pillars nil" do
      snapshot("ranked_keywords", {"top_3" => 9, "total_count" => 125, "striking_distance" => [], "metrics" => {}}, at: 8.days.ago)
      snapshot("ranked_keywords", {"top_3" => 12, "total_count" => 250, "striking_distance" => [], "metrics" => {}})
      snapshot("google_reviews", {"rating" => 4.6, "reviews_count" => 40, "unanswered" => 3, "recent_low" => 0})

      card = Marketing::Scorecard.new(targets: Marketing::Targets.all(template)).to_h
      search = card[:pillars].find { |p| p[:key] == "search" }
      # top_3 12/15 → 80; keywords 250/250 → 100; mean 90. Previous: 60 and 50 → 55.
      expect(search[:score]).to eq(90)
      expect(search[:previous_score]).to eq(55)
      expect(search[:trend]).to eq("up")

      rep = card[:pillars].find { |p| p[:key] == "reputation" }
      # rating 4.6/4.6 → 100; reviews 40/80 → 50; unanswered 3 → 25; mentions unmeasured (skipped).
      expect(rep[:metrics].find { |m| m[:key] == "unanswered" }[:score]).to eq(25)
      expect(rep[:score]).to eq(58)
      expect(rep[:metrics].find { |m| m[:key] == "positive_mentions" }[:value]).to be_nil

      expect(card[:pillars].find { |p| p[:key] == "ai" }[:score]).to be_nil
      expect(card[:overall]).to eq(74) # (90 + 58) / 2
      expect(card[:measured]).to eq(2)
    end

    it "reads a ratio's denominator from the trend point, so Local rankings' pack share is a percentage" do
      snapshot("local_rankings", {"in_map_pack" => 2, "in_top_3_organic" => 1, "not_ranking" => [],
                                  "keywords" => [{"keyword" => "a"}, {"keyword" => "b"}, {"keyword" => "c"}, {"keyword" => "d"}]})
      local = Marketing::Scorecard.new(targets: Marketing::Targets.all(template)).to_h[:pillars].find { |p| p[:key] == "local" }
      pack = local[:metrics].find { |m| m[:key] == "pack_keywords" }
      expect(pack[:value]).to eq(50)   # 2 of 4
      expect(pack[:score]).to eq(83)   # 50 / 60 target
    end

    it "caps a metric at 100 rather than rewarding overshooting a target" do
      snapshot("page_health", {"average_score" => 99.0, "pages" => []})
      site = Marketing::Scorecard.new(targets: Marketing::Targets.all(template)).to_h[:pillars].find { |p| p[:key] == "site" }
      expect(site[:metrics].find { |m| m[:key] == "page_score" }[:score]).to eq(100)
    end
  end

  describe Marketing::Actions do
    def actions(prof = profile, tmpl = template) = Marketing::Actions.new(profile: prof, template: tmpl).to_a

    it "leads with unfinished setup" do
      items = actions(Reports::Profile.new({}))
      expect(items.first[:key]).to eq("setup")
      expect(items.first[:owner]).to eq("you")
      expect(items.first[:body]).to include("business name")
    end

    it "asks for never-run recommended reports, and flags stale ones" do
      snapshot("google_reviews", {"rating" => 4.6, "reviews_count" => 40, "unanswered" => 0, "low_unanswered" => [], "fetched" => 20}, at: 20.days.ago)
      items = actions
      expect(items.map { |i| i[:key] }).to include("run:ranked_keywords", "stale:google_reviews")
      expect(items.find { |i| i[:key] == "run:ranked_keywords" }[:action]).to eq(type: "run_report", kind: "ranked_keywords")
    end

    it "doesn't ask for a report the profile can't run yet" do
      no_domain = Reports::Profile.new("business_name" => "Acme", "location_name" => "Austin,Texas,United States", "tracked_keywords" => "a")
      keys = Marketing::Actions.new(profile: no_domain, template: template).all.map { |i| i[:key] }
      expect(keys).not_to include("run:ranked_keywords") # needs a domain
      expect(keys).to include("run:business_profile")
    end

    it "hands an agent finding to the agent that does that kind of work, and the rest to the marketer" do
      Recommendation.create!(kind: "metadata", title: "Title too long on /prices", impact: 4)
      Recommendation.create!(kind: "content_gap", title: "No page for student storage", impact: 3)
      items = actions
      meta = items.find { |i| i[:title] == "Title too long on /prices" }
      expect(meta).to include(owner: "agent", impact: 4)
      expect(meta[:action]).to include(type: "hand_off", template: "metadata_optimizer")
    end

    it "turns report figures into owned work — owner for reviews and the listing, agent for site problems" do
      snapshot("google_reviews", {"rating" => 4.2, "reviews_count" => 40, "unanswered" => 6, "fetched" => 20, "answered_pct" => 70,
                                  "low_unanswered" => [{"author" => "A", "text" => "Awful", "rating" => 1}]})
      snapshot("business_profile", {"found" => true, "issues" => [{"severity" => "high", "message" => "Listing is marked temporarily closed"}]})
      snapshot("page_health", {"average_score" => 60.0, "pages" => [{"url" => "/", "issues" => [{"severity" => "critical", "message" => "Page not found"}]}]})
      snapshot("citations", {"directories" => [{"domain" => "yelp.com", "found" => false, "manual_only" => false}, {"domain" => "bbb.org", "found" => true, "consistent" => false, "manual_only" => false, "checks" => {"phone" => false, "name" => true}}]})
      Setting.set("citations", "yelp.com" => {"status" => "submitted"})

      items = actions
      by_key = items.index_by { |i| i[:key] }
      expect(by_key["reviews:low"]).to include(owner: "owner", impact: 4)
      expect(by_key["gbp:issues"]).to include(owner: "owner", impact: 5)
      expect(by_key["site:critical"]).to include(owner: "agent", impact: 5)
      expect(by_key["site:critical"][:action]).to include(template: "technical_seo")
      # yelp is already "submitted", so only bbb's NAP problem is raised.
      expect(by_key).not_to have_key("citations:missing")
      expect(by_key["citations:differs"][:body]).to include("bbb.org")
      expect(by_key["citations:differs"][:evidence]).to include(report: "citations")
      # Sorted by impact, capped.
      expect(items.map { |i| i[:impact] }).to eq(items.map { |i| i[:impact] }.sort.reverse)
      expect(items.length).to be <= Marketing::Actions::LIMIT
    end

    it "nudges — at impact 1 — about recommended agents that aren't on, and never turns one on" do
      switch_plugin :ai, on: true
      switch_plugin :agents, on: true
      # Uncapped: nudges are impact 1 and sit behind every never-run report.
      items = Marketing::Actions.new(profile: profile, template: template).all
      nudge = items.find { |i| i[:key] == "agent:reporting_analyst" }
      expect(nudge).to include(owner: "you", impact: 1, title: "Add Reporting Analyst")
      expect(Agent.count).to eq(0)
    end
  end

  describe Marketing::Setup do
    it "writes the same settings the settings pages edit, and only scaffolds or schedules when asked" do
      result = Marketing::Setup.new(template: template).apply(
        business_type: "self_storage", business_name: "Acme Self Storage", domain: "https://www.acmestorage.com/",
        location_name: "Austin,Texas,United States", phone: "(512) 555-0134", address: "120 Main St",
        tracked_keywords: "self storage Austin\nstorage units Austin", citation_directories: %w[yelp.com sparefoot.com],
        map_grid_size: "5", map_spacing_km: "1.5", targets: {"reviews" => "120"}, scaffold: "false", schedule: "0"
      )

      p = Reports::Profile.load
      expect(p.business_name).to eq("Acme Self Storage")
      expect(p.domain).to eq("acmestorage.com")
      expect(p.tracked_keywords).to eq(["self storage Austin", "storage units Austin"])
      expect(p.map_keywords).to eq(["self storage Austin", "storage units Austin"])
      expect(p.brand_terms).to eq(["Acme Self Storage"])
      expect(Setting.get("marketing")).to include("business_type" => "self_storage", "schema_type" => "SelfStorage")
      expect(Marketing::Targets.all(template)["reviews"]).to eq(120.0)
      expect(result.pages_created).to eq(0)
      expect(result.schedule_enabled).to be(false)
      expect(RecurringTask.find_by(recipe_key: "report_refresh")).to be_nil
    end

    it "scaffolds draft pages once and enables the weekly refresh on the template's reports when asked" do
      Page.create!(slug: "faq", title: "Existing FAQ", status: "published", locale: "en")
      result = Marketing::Setup.new(template: template).apply(business_type: "self_storage", business_name: "Acme", location_name: "Austin,Texas,United States", scaffold: "1", schedule: "1")

      expect(result.pages_created).to eq(3) # faq already existed
      expect(Page.where(status: "draft").pluck(:slug)).to contain_exactly("storage-units", "locations", "reviews")
      expect(Page.find_by(slug: "faq").title).to eq("Existing FAQ")
      task = RecurringTask.find_by(recipe_key: "report_refresh")
      expect(task.enabled).to be(true)
      expect(task.params["reports"]).to include("rank_map", "citations")
    end
  end

  describe Marketing::Narrative do
    it "is absent, not wrong, without a model; and caches against the facts when there is one" do
      expect(Marketing::Narrative.available?).to be(false)
      card = Marketing::Scorecard.new(targets: Marketing::Targets.all(template)).to_h
      expect(Marketing::Narrative.refresh!(scorecard: card, actions: [], business_name: "Acme")).to be_nil

      switch_plugin :ai, on: true
      allow(Ai::Zen).to receive(:configured?).and_return(true)
      allow(Ai::Oneshot).to receive(:call).and_return({"summary" => "Nothing measured yet.", "headline" => "Quiet week"})
      first = Marketing::Narrative.refresh!(scorecard: card, actions: [], business_name: "Acme")
      expect(first).to include("summary" => "Nothing measured yet.", "headline" => "Quiet week")
      expect(Ai::Oneshot).to have_received(:call).once
      # Same facts → no second call.
      Marketing::Narrative.refresh!(scorecard: card, actions: [], business_name: "Acme")
      expect(Ai::Oneshot).to have_received(:call).once
      # The prompt hands over computed facts only — never a report's data.
      expect(Ai::Oneshot).to have_received(:call).with(hash_including(prompt: a_string_including("the ONLY numbers you may use")))
    end
  end
end

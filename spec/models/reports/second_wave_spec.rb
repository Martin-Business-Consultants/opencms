# frozen_string_literal: true

require "rails_helper"

# The twelve reports added in the second wave. As with the first, the risk is
# in the reduction — each is fed a response shaped like the documented one
# and the specs assert on what comes out, plus the request that went in.
RSpec.describe "Second-wave report definitions" do
  before { Rails.cache.clear; Report.destroy_all }

  class Wave2Client
    attr_reader :calls

    LOCATIONS = [
      {"location_code" => 2826, "location_name" => "United Kingdom", "country_iso_code" => "GB",
       "available_languages" => [{"language_code" => "en"}]}
    ].freeze
    CITIES = [{"location_code" => 1_006_886, "location_name" => "Cardiff,Wales,United Kingdom", "location_type" => "City"}].freeze

    def initialize(responses = {}, tasks = {})
      @responses = responses
      @tasks = tasks
      @calls = []
    end

    def get(path)
      @calls << [:get, path]
      path.include?("/locations/") ? CITIES : LOCATIONS
    end

    def post(path, task)
      @calls << [:post, path, task]
      wrap(fetch_response(path, task))
    end

    def post_many(path, tasks)
      @calls << [:post_many, path, tasks]
      Array(@responses.fetch(path)).map { |r| r && wrap(r) }
    end

    def post_task(path, task)
      @calls << [:post_task, path, task]
      {id: "task-1", cost: 0.001}
    end

    def task_get(path, id)
      @calls << [:task_get, path, id]
      @polls = (@polls || 0) + 1
      @polls < 2 ? nil : wrap(@tasks.fetch(path))
    end

    private

    def fetch_response(path, task)
      r = @responses.fetch(path)
      r.is_a?(Proc) ? r.call(task) : r
    end

    def wrap(result)
      DataForSeo::Response.new(result: Array(result), cost: 0.01, task_id: "x", time: "1")
    end
  end

  def profile(data = {}, general = {})
    Reports::Profile.new({"domain" => "acme.co.uk", "business_name" => "Acme Storage",
                          "location_name" => "Cardiff,Wales,United Kingdom",
                          "tracked_keywords" => "storage cardiff\nself storage",
                          "competitors" => "bigyellow.co.uk", "brand_terms" => "Acme Storage"}.merge(data), general)
  end

  def run(klass, client, data = {})
    klass.new(profile: profile(data), client: client).call
  end

  describe Reports::Definitions::AiAnswers do
    it "asks both assistants from the business's city and reads the answers for us and for competitors" do
      answer = lambda do |task|
        text = task[:user_prompt] == "storage cardiff" ? "Try Acme Storage on High St, or Big Yellow." : "Big Yellow is popular."
        [{"model_name" => task[:model_name], "items" => [{"type" => "message", "sections" => [{"type" => "text", "text" => text,
          "annotations" => [{"url" => "https://www.bigyellow.co.uk/cardiff"}, {"url" => "https://yell.com/x"}]}]}]}]
      end
      client = Wave2Client.new(described_class::PLATFORMS.values.to_h { |s| [s[:path], answer] })

      data = run(described_class, client)

      posts = client.calls.select { |c| c.first == :post }
      expect(posts.length).to eq(4) # 2 prompts × 2 platforms
      chat = posts.find { |c| c[1].include?("chat_gpt") }[2]
      gemini = posts.find { |c| c[1].include?("gemini") }[2]
      expect(chat).to include(web_search: true, web_search_country_iso_code: "GB", web_search_city: "Cardiff")
      # Gemini's endpoint has no location fields (40501 if sent); it is told
      # where the user is in the system message instead.
      expect(gemini).to include(web_search: true)
      expect(gemini).not_to have_key(:web_search_country_iso_code)
      expect(gemini).not_to have_key(:web_search_city)
      expect(gemini[:system_message]).to include("The user is in Cardiff, United Kingdom")
      expect(chat[:system_message]).not_to include("The user is in")
      expect(data[:answers]).to eq(4)
      expect(data[:mentioned_in]).to eq(2)
      expect(data[:mention_rate]).to eq(50)
      expect(data[:competitors_mentioned]).to eq([{key: "bigyellow.co.uk", count: 4}])
      expect(data[:cited_domains].map { |c| c[:key] }).to contain_exactly("bigyellow.co.uk", "yell.com")
    end

    it "records a failed platform without failing the report" do
      failing = ->(_) { raise DataForSeo::Error, "model unavailable" }
      ok = ->(_) { [{"items" => [{"type" => "message", "sections" => [{"type" => "text", "text" => "Acme Storage."}]}]}] }
      paths = described_class::PLATFORMS.transform_values { |s| s[:path] }
      client = Wave2Client.new(paths["chat_gpt"] => failing, paths["gemini"] => ok)

      data = run(described_class, client, "tracked_keywords" => "a")
      expect(data[:answers]).to eq(1)
      expect(data[:rows].find { |r| r[:platform] == "chat_gpt" }[:error]).to match(/model unavailable/)
    end
  end

  describe Reports::Definitions::KeywordDemand do
    it "sums the seasonality, finds the peak and the year-on-year change" do
      months = ->(base) { (1..13).map { |i| {"year" => 2025 + (i > 4 ? 1 : 0), "month" => ((i + 7) % 12) + 1, "search_volume" => base + (i == 13 ? 50 : 0)} } }
      client = Wave2Client.new(described_class::PATH => [
        {"keyword" => "storage cardiff", "search_volume" => 900, "competition" => "HIGH", "competition_index" => 80, "cpc" => 1.5, "monthly_searches" => months.call(100)},
        {"keyword" => "self storage", "search_volume" => 0, "cpc" => nil, "monthly_searches" => []}
      ])

      data = run(described_class, client)

      expect(client.calls.last[2]).to include(location_code: 2826, keywords: ["storage cardiff", "self storage"])
      expect(data[:total_volume]).to eq(900)
      expect(data[:avg_cpc]).to eq(1.5)
      expect(data[:no_demand]).to eq(["self storage"])
      expect(data[:months].length).to eq(13)
      expect(data[:yoy_pct]).to eq(50.0)
    end
  end

  describe Reports::Definitions::Competitors do
    it "marks known competitors and the ones bigger than us, and drops our own row" do
      client = Wave2Client.new(described_class::PATH => [{"total_count" => 3, "items" => [
        {"domain" => "acme.co.uk", "intersections" => 40, "full_domain_metrics" => {"organic" => {"count" => 100, "etv" => 500}}},
        {"domain" => "bigyellow.co.uk", "intersections" => 30, "avg_position" => 8.2, "full_domain_metrics" => {"organic" => {"count" => 5000, "etv" => 90_000, "pos_1" => 50, "pos_2_3" => 100, "pos_4_10" => 400}}},
        {"domain" => "tiny.co.uk", "intersections" => 5, "full_domain_metrics" => {"organic" => {"count" => 20}}}
      ]}])

      data = run(described_class, client)

      expect(data[:our_keywords]).to eq(100)
      expect(data[:competitors].map { |c| c[:domain] }).to eq(%w[bigyellow.co.uk tiny.co.uk])
      big = data[:competitors].first
      expect(big).to include(known: true, bigger: true, top_10: 550)
      expect(data[:competitors].last[:bigger]).to be(false)
      expect(data[:missing_known]).to eq([])
    end
  end

  describe Reports::Definitions::KeywordOpportunities do
    it "cross-references the latest Ranked keywords run and surfaces the easy wins" do
      Report.create!(kind: "ranked_keywords", status: "complete", data: {"keywords" => [{"keyword" => "Storage Cardiff", "position" => 4}]})
      client = Wave2Client.new(described_class::PATH => [{"total_count" => 3, "items" => [
        {"keyword" => "storage cardiff", "keyword_info" => {"search_volume" => 900}, "keyword_properties" => {"keyword_difficulty" => 20}, "search_intent_info" => {"main_intent" => "commercial"}},
        {"keyword" => "student storage cardiff", "keyword_info" => {"search_volume" => 200, "cpc" => 0.8}, "keyword_properties" => {"keyword_difficulty" => 12}, "search_intent_info" => {"main_intent" => "transactional"}},
        {"keyword" => "hard one", "keyword_info" => {"search_volume" => 5000}, "keyword_properties" => {"keyword_difficulty" => 75}}
      ]}])

      data = run(described_class, client)

      expect(data[:cross_referenced]).to be(true)
      expect(data[:ideas].first[:ranking_position]).to eq(4)
      expect(data[:easy_wins].map { |k| k[:keyword] }).to eq(["student storage cardiff"])
      expect(data[:by_intent]).to include("commercial" => 1, "transactional" => 1, "unknown" => 1)
    end
  end

  describe Reports::Definitions::VisibilityHistory do
    it "orders the months and computes the 12-month change" do
      items = (1..14).map { |i| {"year" => 2025 + ((i + 6) / 12 == 0 ? 0 : 1) - (i + 6 <= 12 ? 0 : 0), "month" => ((i + 6) % 12) + 1, "metrics" => {"organic" => {"count" => 100 + i * 10, "pos_1" => 1, "pos_2_3" => 2, "pos_4_10" => 5, "etv" => 50 + i, "is_new" => 3, "is_lost" => 1}}} }
      items.each_with_index { |it, idx| it["year"] = 2025 + (idx >= 5 ? 1 : 0) }
      client = Wave2Client.new(described_class::PATH => [{"items" => items.shuffle}])

      data = run(described_class, client)

      expect(data[:months].first[:ranked]).to eq(110)
      expect(data[:months].last[:ranked]).to eq(240)
      expect(data[:latest][:top_10]).to eq(8)
      expect(data[:change_12m][:ranked_pct]).to eq(100.0) # 240 vs 120
    end
  end

  describe Reports::Definitions::SearchTrends do
    let(:graph) { [{"items" => [{"type" => "google_trends_graph", "data" => [{"date_from" => "2026-08-01", "values" => [40, 10]}, {"date_from" => "2026-08-08", "values" => [100, 20]}]}]}] }

    it "takes the graph live — with no item_types — and the map and queries as awaited tasks" do
      tasks = {described_class::TASK_PATH => [{"items" => [
        {"type" => "google_trends_map", "data" => [{"geo_name" => "Cardiff", "values" => [100, 50], "max_value_index" => 0}, {"geo_name" => "Nowhere", "values" => [0, 0]}]},
        {"type" => "google_trends_queries_list", "data" => {"top" => [{"query" => "storage near me", "value" => "100"}], "rising" => [{"query" => "student storage", "value" => "Breakout"}]}}
      ]}]}
      client = Wave2Client.new({described_class::PATH => graph}, tasks)
      definition = described_class.new(profile: profile, client: client)
      allow(definition).to receive(:sleep)

      data = definition.call

      live = client.calls.find { |c| c.first == :post }[2]
      expect(live).to include(keywords: ["storage cardiff", "self storage"], time_range: "past_12_months")
      # The field the live API refuses.
      expect(live).not_to have_key(:item_types)
      posted = client.calls.select { |c| c.first == :post_task }.map { |c| c[2][:item_types] }
      expect(posted).to eq([["google_trends_map"], ["google_trends_queries_list"]])
      expect(data[:graph].last).to include(date: "2026-08-08", total: 120, k0: 100, k1: 20)
      expect(data[:regions].map { |r| r[:name] }).to eq(["Cardiff"])
      expect(data[:rising_queries].first[:value]).to eq("Breakout")
      expect(data[:peak]).to eq("2026-08-08")
      expect(definition.warnings).to eq([])
    end

    it "keeps the graph when a task fails, and says what is missing" do
      client = Wave2Client.new({described_class::PATH => graph}, {})
      allow(client).to receive(:task_get).and_raise(DataForSeo::Error.new("DataForSEO task failed (40501): Invalid Field: 'x'."))
      definition = described_class.new(profile: profile, client: client)
      allow(definition).to receive(:sleep)

      data = definition.call

      expect(data[:graph].length).to eq(2)
      expect(data[:regions]).to eq([])
      expect(data[:rising_queries]).to eq([])
      expect(definition.warnings.length).to eq(2)
      expect(definition.warnings.first).to match(/google trends map unavailable/)
    end
  end

  describe Reports::Definitions::MapsRankings do
    it "finds our listing by domain, counts who is above, and keeps our coordinates" do
      pack = [
        {"type" => "maps_search", "rank_group" => 1, "title" => "Big Yellow", "domain" => "bigyellow.co.uk", "rating" => {"value" => 4.5, "votes_count" => 300}},
        {"type" => "maps_search", "rank_group" => 2, "title" => "Acme Storage", "domain" => "www.acme.co.uk", "rating" => {"value" => 4.7, "votes_count" => 88}, "latitude" => 51.48, "longitude" => -3.18, "category" => "Self-storage facility", "is_claimed" => true}
      ]
      client = Wave2Client.new(described_class::PATH => [[{"items" => pack}], [{"items" => pack.first(1)}]])

      data = run(described_class, client)

      expect(client.calls.last[2].first).to include(location_code: 1_006_886, device: "mobile")
      expect(data[:keywords].first).to include(position: 2, rating: 4.7)
      expect(data[:keywords].first[:above].map { |a| a[:title] }).to eq(["Big Yellow"])
      expect(data[:not_found]).to eq(["self storage"])
      expect(data[:in_top_3]).to eq(1)
      expect(data[:listing]).to include(latitude: 51.48, category: "Self-storage facility")
      expect(data[:rivals].first).to include(title: "Big Yellow", appearances: 2)
    end

    it "gives a failed keyword the same shape as a good one" do
      client = Wave2Client.new(described_class::PATH => [nil])
      data = run(described_class, client, "tracked_keywords" => "a")

      expect(data[:keywords].first).to include(keyword: "a", error: "No result returned", position: nil, above: [], listing: nil, results: 0)
      expect(data[:not_found]).to eq([])
      expect(data[:in_top_3]).to eq(0)
    end
  end

  describe Reports::Definitions::LocalCompetitors do
    it "locates us on Maps, then lists the category around us and ranks us in it" do
      ours = {"type" => "maps_search", "title" => "Acme Storage", "domain" => "acme.co.uk", "cid" => "999", "latitude" => 51.48, "longitude" => -3.18, "category" => "Self-storage facility"}
      listings = [
        {"title" => "Big Yellow", "domain" => "bigyellow.co.uk", "cid" => "1", "rating" => {"value" => 4.5, "votes_count" => 300}, "is_claimed" => true, "latitude" => 51.50, "longitude" => -3.20},
        {"title" => "Acme Storage", "domain" => "acme.co.uk", "cid" => "999", "rating" => {"value" => 4.7, "votes_count" => 88}, "is_claimed" => true, "latitude" => 51.48, "longitude" => -3.18},
        {"title" => "Shed Co", "domain" => "", "cid" => "2", "rating" => {"value" => 3.9, "votes_count" => 12}, "is_claimed" => false, "latitude" => 51.40, "longitude" => -3.10}
      ]
      client = Wave2Client.new(described_class::FIND_PATH => [{"items" => [ours]}], described_class::PATH => [{"items" => listings}])

      data = run(described_class, client)

      search = client.calls.find { |c| c[1] == described_class::PATH }[2]
      expect(search[:location_coordinate]).to eq("51.48,-3.18,15")
      expect(search[:filters]).to eq([["category", "=", "Self-storage facility"]])
      expect(data[:competitors].map { |c| c[:title] }).to eq(["Big Yellow", "Shed Co"])
      expect(data[:ours]).to include(review_rank: 2, rating_rank: 1)
      expect(data[:claimed_pct]).to eq(50)
      expect(data[:competitors].first[:distance_km]).to be_between(2.0, 3.0)
    end

    it "fails with the fix when the business isn't on Maps" do
      client = Wave2Client.new(described_class::FIND_PATH => [{"items" => []}])
      expect { run(described_class, client) }.to raise_error(DataForSeo::Error, /Couldn't find "Acme Storage" on Google Maps/)
    end
  end

  describe Reports::Definitions::GoogleReviews do
    it "posts a task, waits for it, and reads the shape underneath the rating" do
      reviews = [
        {"type" => "google_reviews_search", "rating" => {"value" => 1}, "review_text" => "Awful", "time_ago" => "2 days ago", "profile_name" => "A", "owner_answer" => nil},
        {"type" => "google_reviews_search", "rating" => {"value" => 5}, "review_text" => "Great", "time_ago" => "a week ago", "profile_name" => "B", "owner_answer" => "Thanks!"},
        {"type" => "google_reviews_search", "rating" => {"value" => 4}, "review_text" => "", "time_ago" => "a month ago", "profile_name" => "C", "local_guide" => true}
      ]
      client = Wave2Client.new({}, {described_class::PATH => [{"title" => "Acme Storage", "rating" => {"value" => 4.6}, "reviews_count" => 120, "items" => reviews}]})
      definition = described_class.new(profile: profile("place_id" => "ChIJx"), client: client)
      allow(definition).to receive(:sleep)

      data = definition.call

      post = client.calls.find { |c| c.first == :post_task }
      expect(post[2]).to include(place_id: "ChIJx", depth: 50, sort_by: "newest", location_code: 1_006_886)
      expect(client.calls.count { |c| c.first == :task_get }).to eq(2)
      expect(data).to include(rating: 4.6, reviews_count: 120, fetched: 3, unanswered: 2, recent_low: 1)
      expect(data[:distribution]).to eq({"1" => 1, "2" => 0, "3" => 0, "4" => 1, "5" => 1})
      expect(data[:low_unanswered].map { |r| r[:author] }).to eq(["A"])
      expect(definition.cost).to be_within(0.0001).of(0.011)
    end
  end

  describe Reports::Definitions::Backlinks do
    let(:responses) do
      {
        described_class::SUMMARY => [{"rank" => 120, "backlinks" => 400, "referring_domains" => 40, "referring_domains_nofollow" => 10, "referring_main_domains" => 35, "referring_pages" => 300, "backlinks_spam_score" => 8, "broken_backlinks" => 2, "referring_links_tld" => {"uk" => 30, "com" => 10}, "referring_links_platform_types" => {"cms" => 20}}],
        described_class::DOMAINS => [{"items" => [{"domain" => "yell.com", "rank" => 300, "backlinks" => 12, "referring_pages" => 12, "backlinks_spam_score" => 5, "first_seen" => "2024-01-02 00:00:00 +00:00"}]}],
        described_class::ANCHORS => [{"items" => [{"anchor" => "acme storage", "backlinks" => 20, "referring_domains" => 8, "rank" => 100}, {"anchor" => "", "backlinks" => 5}]}],
        described_class::HISTORY => [{"items" => [{"date" => "2026-08-31 00:00:00 +00:00", "backlinks" => 400, "referring_domains" => 40, "rank" => 120}, {"date" => "2026-07-31 00:00:00 +00:00", "backlinks" => 380, "referring_domains" => 38, "rank" => 118}]}],
        described_class::NEW_LOST => [{"items" => [{"date" => "2026-08-31 00:00:00 +00:00", "new_referring_domains" => 3, "lost_referring_domains" => 1, "new_backlinks" => 20, "lost_backlinks" => 4}]}]
      }
    end

    it "makes the five calls, never sends date_from, and merges the two timeseries by month" do
      client = Wave2Client.new(responses)

      data = run(described_class, client)

      paths = client.calls.map { |c| c[1] }
      expect(paths).to eq([described_class::SUMMARY, described_class::DOMAINS, described_class::ANCHORS, described_class::HISTORY, described_class::NEW_LOST])
      # The field the live API rejected with 40501, despite the docs.
      client.calls.select { |c| [described_class::HISTORY, described_class::NEW_LOST].include?(c[1]) }.each do |c|
        expect(c[2]).not_to have_key(:date_from)
        expect(c[2]).to include(group_range: "month")
      end
      expect(data[:summary]).to include(rank: 120, referring_domains: 40, dofollow_pct: 75, spam_score: 8.0)
      expect(data[:referring_domains].first).to include(domain: "yell.com", first_seen: "2024-01-02")
      expect(data[:anchors].last[:anchor]).to eq("(empty)")
      expect(data[:history].map { |h| h[:date] }).to eq(%w[2026-07-01 2026-08-01])
      expect(data[:history].last).to include(referring_domains: 40, new_domains: 3, lost_domains: 1, new_backlinks: 20)
      expect(data[:history].first).to include(new_domains: 0, lost_domains: 0)
      expect(data[:history_note]).to be_nil
      expect(data[:tlds].first).to eq({key: "uk", count: 30})
      expect(described_class.trend_point(data.deep_stringify_keys)).to include("referring_domains" => 40, "spam_score" => 8.0)
    end

    it "keeps the report when a history call fails, and says so" do
      failing = responses.merge(described_class::HISTORY => ->(_) { raise DataForSeo::Error, "DataForSEO task failed (40501): Invalid Field: 'date_from'." })
      client = Wave2Client.new(failing)

      data = run(described_class, client)

      expect(data[:summary][:rank]).to eq(120)
      expect(data[:history]).to eq([])
      expect(data[:history_note]).to match(/History unavailable: .*40501/)
    end
  end

  describe Reports::Definitions::Lighthouse do
    it "reads the four category scores and the metric audits from raw Lighthouse JSON" do
      lh = lambda do |task|
        [{"finalUrl" => task[:url], "lighthouseVersion" => "12.0",
          "categories" => {"performance" => {"score" => 0.61}, "accessibility" => {"score" => 0.9}, "best-practices" => {"score" => 1.0}, "seo" => {"score" => 0.85}},
          "audits" => {
            "largest-contentful-paint" => {"id" => "largest-contentful-paint", "numericValue" => 3400.4, "displayValue" => "3.4 s", "score" => 0.3, "scoreDisplayMode" => "numeric", "title" => "LCP"},
            "cumulative-layout-shift" => {"id" => "cumulative-layout-shift", "numericValue" => 0.1234, "displayValue" => "0.123", "score" => 0.8, "scoreDisplayMode" => "numeric", "title" => "CLS"},
            "uses-optimized-images" => {"id" => "uses-optimized-images", "score" => 0.2, "scoreDisplayMode" => "metricSavings", "title" => "Efficiently encode images", "displayValue" => "Potential savings of 400 KiB"},
            "informative-thing" => {"id" => "informative-thing", "score" => 0, "scoreDisplayMode" => "informative", "title" => "Not a failure"}
          }}]
      end
      client = Wave2Client.new(described_class::PATH => lh)

      data = run(described_class, client, "audit_urls" => "https://acme.co.uk/\nhttps://acme.co.uk/prices")

      expect(client.calls.first[2]).to include(for_mobile: true, categories: %w[performance accessibility best_practices seo])
      page = data[:pages].first
      expect(page[:scores]).to eq("performance" => 61, "accessibility" => 90, "best_practices" => 100, "seo" => 85)
      expect(page[:metrics]["LCP"]).to include(value: 3400.0, display: "3.4 s")
      expect(page[:metrics]["CLS"][:value]).to eq(0.123)
      expect(page[:failed_audits].map { |a| a[:id] }).to contain_exactly("largest-contentful-paint", "uses-optimized-images")
      expect(data[:averages]["performance"]).to eq(61.0)
      expect(data[:failing].first).to include(pages: 2)
    end
  end

  describe Reports::Definitions::WebMentions do
    it "merges the per-term summaries and computes the positive share" do
      client = Wave2Client.new(described_class::PATH => ->(task) {
        [{"total_count" => task[:keyword] == "Acme Storage" ? 30 : 10,
          "connotation_types" => {"positive" => 12, "negative" => 3, "neutral" => 5},
          "sentiment_connotations" => {"happiness" => 8, "anger" => 2},
          "top_domains" => [{"domain" => "walesonline.co.uk", "count" => 6}, {"domain" => "yell.com", "count" => 4}],
          "page_types" => {"news" => 10, "blogs" => 5}, "countries" => {"GB" => 25}}]
      })

      data = run(described_class, client, "brand_terms" => "Acme Storage\nAcme Self Storage")

      expect(client.calls.length).to eq(2)
      expect(data[:total]).to eq(40)
      expect(data[:connotations]).to eq("positive" => 24, "negative" => 6, "neutral" => 10)
      expect(data[:positive_pct]).to eq(60)
      expect(data[:top_domains].first).to eq({key: "walesonline.co.uk", count: 12})
      expect(data[:by_term].map { |t| t[:count] }).to eq([30, 10])
    end
  end

  describe Reports::Definitions::RankMap do
    let(:ours) { {"type" => "maps_search", "title" => "Acme Storage", "domain" => "acme.co.uk", "cid" => "999", "latitude" => 51.48, "longitude" => -3.18, "category" => "Self-storage facility", "rating" => {"value" => 4.7, "votes_count" => 88}} }
    let(:rival) { {"type" => "maps_search", "title" => "Big Yellow", "cid" => "111", "rank_group" => 1, "latitude" => 51.49, "longitude" => -3.19, "rating" => {"value" => 4.5, "votes_count" => 300}} }

    # A 3×3 grid, one keyword: us #1 in the centre, #5 to the north, absent
    # to the south, Big Yellow #1 everywhere else.
    def serp_for(task)
      lat = task[:location_coordinate].split(",").first.to_f
      me = ours.merge("rank_group" => lat > 51.485 ? 5 : 1)
      items = lat < 51.475 ? [rival] : [rival.merge("rank_group" => me["rank_group"] == 1 ? 2 : 1), me]
      [{"items" => items.sort_by { |i| i["rank_group"] }}]
    end

    it "asks the keyword from every grid point as a coordinate, and reads the shape" do
      client = Wave2Client.new(described_class::FIND_PATH => [{"items" => [ours]}])
      # fetch_many isn't table-driven in the fake; answer per task instead.
      allow(client).to receive(:post_many) do |path, tasks|
        client.calls << [:post_many, path, tasks]
        tasks.map { |t| DataForSeo::Response.new(result: serp_for(t), cost: 0.002, task_id: "x", time: "1") }
      end

      data = run(described_class, client, "map_grid_size" => 3, "map_spacing_km" => 1.0, "map_keywords" => "storage cardiff")

      tasks = client.calls.select { |c| c.first == :post_many }.flat_map { |c| c[2] }
      expect(tasks.length).to eq(9)
      expect(tasks.first).to include(keyword: "storage cardiff", depth: 20, device: "mobile", language_code: "en")
      expect(tasks.first[:location_coordinate]).to match(/\A51\.48\d+,-3\.1\d+,14z\z/)
      expect(tasks.first).not_to have_key(:location_code)
      # Row 0 is north, so its latitude is higher than the centre's.
      north = tasks.first[:location_coordinate].split(",").first.to_f
      expect(north).to be > 51.48

      grid = data[:keywords].first
      expect(grid[:cells].length).to eq(9)
      centre = grid[:cells].find { |c| c[:row] == 1 && c[:col] == 1 }
      expect(centre[:position]).to eq(1)
      expect(centre[:latitude]).to eq(51.48)
      expect(grid[:cells].select { |c| c[:row] == 0 }.map { |c| c[:position] }).to eq([5, 5, 5])
      expect(grid[:cells].select { |c| c[:row] == 2 }.map { |c| c[:position] }).to eq([nil, nil, nil])
      expect(grid[:found_pct]).to eq(67)
      expect(grid[:share_top_3]).to eq(33)
      expect(grid).to include(best: 1, worst: 5)
      expect(data[:owners].first).to include(title: "Big Yellow", cells: 6)
      expect(data[:business]).to include(title: "Acme Storage", latitude: 51.48)
      expect(described_class.trend_point(data.deep_stringify_keys)).to include("share_top_3" => 33.0, "cells" => 9)
    end

    it "fails with the fix when the business isn't on Maps" do
      client = Wave2Client.new(described_class::FIND_PATH => [{"items" => []}])
      expect { run(described_class, client, "map_keywords" => "a") }.to raise_error(DataForSeo::Error, /Couldn't find "Acme Storage" on Google Maps/)
    end
  end

  describe Reports::Definitions::Citations do
    let(:nap_profile) { {"business_name" => "Acme Storage", "phone" => "(512) 555-0134", "address" => "120 Main St, Austin, TX 78701", "location_name" => "Austin,Texas,United States", "citation_directories" => "yelp.com\nbbb.org\nmaps.apple.com"} }

    def serp(domain_hit)
      ->(task) {
        domain = task[:keyword][/site:(\S+)/, 1]
        domain_hit.key?(domain) ? [{"items" => [{"type" => "organic", "url" => "https://www.#{domain}/biz/acme-storage", "title" => "Acme Storage - #{domain}"}]}] : [{"items" => [{"type" => "organic", "url" => "https://other.com/x", "title" => "not it"}]}]
      }
    end

    it "finds each listing with a site: search, reads it, and checks the NAP" do
      pages = {
        "yelp.com" => "# Acme Storage\n120 Main St Austin, TX 78701 · Phone: (512) 555-0134",
        "bbb.org" => "Acme Storage LLC — 500 Other Rd, Austin TX 78702. Call 512-555-9999"
      }
      client = Wave2Client.new(
        described_class::SEARCH => serp({"yelp.com" => true, "bbb.org" => true}),
        described_class::PARSE => ->(task) { [{"items" => [{"page_as_markdown" => pages.fetch(task[:url][%r{www\.([^/]+)}, 1])}]}] }
      )

      data = run(described_class, client, nap_profile)

      searches = client.calls.select { |c| c.first == :post && c[1] == described_class::SEARCH }.map { |c| c[2][:keyword] }
      expect(searches).to eq(['site:yelp.com "Acme Storage" Austin', 'site:bbb.org "Acme Storage" Austin'])
      expect(client.calls.select { |c| c.first == :post && c[1] == described_class::PARSE }.first[2]).to include(markdown_view: true)

      yelp = data[:directories].find { |r| r[:domain] == "yelp.com" }
      expect(yelp).to include(found: true, consistent: true)
      expect(yelp[:checks]).to eq(name: true, phone: true, address: true)

      bbb = data[:directories].find { |r| r[:domain] == "bbb.org" }
      expect(bbb).to include(found: true, consistent: false)
      expect(bbb[:checks]).to eq(name: true, phone: false, address: false)

      apple = data[:directories].find { |r| r[:domain] == "maps.apple.com" }
      expect(apple).to include(manual_only: true, found: nil)
      expect(apple[:reason]).to match(/Apple Business Connect/)

      expect(data).to include(checked: 2, found: 2, consistent: 1, missing: [], inconsistent: ["bbb.org"])
      expect(data[:nap_source]).to eq("settings")
      expect(described_class.trend_point(data.deep_stringify_keys)).to eq("found" => 2, "consistent" => 1, "missing" => 0, "inconsistent" => 1)
    end

    it "calls a directory missing only when no result is on that domain, and doesn't read anything for it" do
      client = Wave2Client.new(described_class::SEARCH => serp({}), described_class::PARSE => [])
      data = run(described_class, client, nap_profile)

      expect(data[:missing]).to eq(%w[yelp.com bbb.org])
      expect(client.calls.count { |c| c.first == :post && c[1] == described_class::PARSE }).to eq(0)
    end

    it "falls back to Google's NAP from the latest Business profile, and leaves unchecked what it has no reference for" do
      Report.create!(kind: "business_profile", status: "complete", data: {"found" => true, "phone" => "512-555-0134", "address" => ""})
      client = Wave2Client.new(
        described_class::SEARCH => serp({"yelp.com" => true}),
        described_class::PARSE => [{"items" => [{"page_as_markdown" => "Acme Storage (512) 555-0134"}]}]
      )
      data = run(described_class, client, nap_profile.merge("phone" => "", "address" => "", "citation_directories" => "yelp.com"))

      yelp = data[:directories].first
      expect(data[:nap_source]).to eq("business_profile")
      expect(yelp[:checks]).to eq(name: true, phone: true, address: nil)
      expect(yelp[:consistent]).to be(true)
      expect(yelp[:unchecked]).to eq([:address])
    end

    it "never sends a city-level location — a site: search is country-scoped" do
      client = Wave2Client.new(described_class::SEARCH => serp({}), described_class::PARSE => [])
      run(described_class, client, nap_profile.merge("citation_directories" => "yelp.com"))
      task = client.calls.find { |c| c.first == :post }[2]
      # The fake's list has no United States, so this is the country fallback —
      # the point is that it's a country CODE and never a city name.
      expect(task[:location_code]).to eq(DataForSeo::Locations::DEFAULT_CODE)
      expect(task).not_to have_key(:location_name)
    end
  end

  describe "the catalog" do
    it "registers all twenty-one with a granularity, a list where needed, and trend metrics" do
      expect(Reports::Catalog.all.length).to eq(21)
      Reports::Catalog.all.each do |d|
        expect(%i[city country none]).to include(d.location_granularity), d.key
        expect(DataForSeo::Locations::APIS).to have_key(d.locations_api), d.key if d.location_granularity != :none
        expect(d.trend_metrics).not_to be_empty, d.key
        expect(d.trend_point({})).to be_a(Hash), d.key
      end
    end
  end

  describe "Definition#fetch drop-and-retry" do
    # A client that refuses a named optional field once, then accepts.
    class RefusingClient
      attr_reader :calls

      def initialize(refuse)
        @refuse = refuse
        @calls = []
      end

      def post(_path, task)
        @calls << task
        bad = @refuse.find { |f| task.key?(f) }
        raise DataForSeo::Error.new("DataForSEO task for x failed (40501): Invalid Field: '#{bad}'.", status_code: 40_501) if bad

        DataForSeo::Response.new(result: [{"ok" => true}], cost: 0.01, task_id: "t", time: "1")
      end
    end

    let(:definition) { Reports::Definition.new(profile: profile, client: nil) }

    def fetch_with(client, task)
      definition.instance_variable_set(:@client, client)
      definition.send(:fetch, "some/endpoint/live", task)
    end

    it "drops the field the API named and retries, recording that it did" do
      client = RefusingClient.new(%i[web_search_city])
      response = fetch_with(client, {user_prompt: "hi", web_search: true, web_search_city: "Cardiff"})

      expect(response.first).to eq("ok" => true)
      expect(client.calls.length).to eq(2)
      expect(client.calls.last).not_to have_key(:web_search_city)
      expect(definition.warnings).to eq(["some/endpoint refused 'web_search_city'; sent without."])
    end

    it "drops several in turn, up to the ceiling" do
      client = RefusingClient.new(%i[a b c])
      fetch_with(client, {keyword: "k", a: 1, b: 2, c: 3})
      expect(client.calls.length).to eq(4)
      expect(definition.warnings.first).to include("'a', 'b', and 'c'")

      client = RefusingClient.new(%i[a b c d])
      expect { fetch_with(client, {keyword: "k", a: 1, b: 2, c: 3, d: 4}) }.to raise_error(DataForSeo::Error, /'d'/)
    end

    it "never drops a required field, and re-raises anything that isn't a 40501 about a field it sent" do
      client = RefusingClient.new(%i[keyword])
      expect { fetch_with(client, {keyword: "k"}) }.to raise_error(DataForSeo::Error, /'keyword'/)
      expect(client.calls.length).to eq(1)

      other = instance_double(DataForSeo::Client)
      allow(other).to receive(:post).and_raise(DataForSeo::Error.new("DataForSEO error 40200: not enough money", status_code: 40_200))
      expect { fetch_with(other, {keyword: "k", extra: 1}) }.to raise_error(DataForSeo::Error, /40200/)
    end
  end
end

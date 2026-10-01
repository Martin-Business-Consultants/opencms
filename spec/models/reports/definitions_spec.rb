# frozen_string_literal: true

require "rails_helper"

# The definitions reduce large, awkward DataForSEO payloads to the handful of
# numbers a person reads. These specs feed each one a response shaped like the
# documented one and assert on the reduction — that is where the bugs live,
# not in the HTTP.
RSpec.describe "Reports definitions" do
  # DataForSeo::Locations caches under a global key; without this, one spec
  # file's location fixture leaks into another's.
  before { Rails.cache.clear }

  # A stand-in for the client that hands back canned results and records what
  # it was asked for, so a spec can assert on the request as well as the
  # reduction.
  class FakeClient
    attr_reader :calls

    # The supported-locations lists reports resolve against: a country list
    # (with the ISO codes the city lists are filed under) and a UK city list.
    LOCATIONS = [
      {"location_code" => 2840, "location_name" => "United States", "country_iso_code" => "US",
       "available_languages" => [{"language_code" => "en"}]},
      {"location_code" => 2826, "location_name" => "United Kingdom", "country_iso_code" => "GB",
       "available_languages" => [{"language_code" => "en"}]}
    ].freeze
    CITIES = [
      {"location_code" => 1_006_886, "location_name" => "Cardiff,Wales,United Kingdom", "location_type" => "City"}
    ].freeze

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def get(path)
      @calls << [path, nil]
      path.include?("/locations/") ? CITIES : LOCATIONS
    end

    def post(path, task)
      @calls << [path, task]
      wrap(@responses.fetch(path))
    end

    def post_many(path, tasks)
      @calls << [path, tasks]
      Array(@responses.fetch(path)).map { |result| result && wrap(result) }
    end

    private

    def wrap(result)
      DataForSeo::Response.new(result: Array(result), cost: 0.01, task_id: "x", time: "1")
    end
  end

  def profile(data = {}, general = {})
    Reports::Profile.new(data, general)
  end

  describe Reports::Definitions::LlmVisibility do
    let(:response) do
      [{
        "aggregated_metrics" => {
          "total" => {"mentions" => 42, "ai_search_volume" => 900},
          "platform" => [
            {"key" => "chat_gpt", "mentions" => 30, "ai_search_volume" => 600},
            {"key" => "google", "mentions" => 12, "ai_search_volume" => 300}
          ],
          "sources_domain" => [
            {"key" => "yell.com", "mentions" => 5, "ai_search_volume" => 50},
            {"key" => "trustpilot.com", "mentions" => 9, "ai_search_volume" => 90},
            {"key" => "", "mentions" => 3, "ai_search_volume" => 0}
          ],
          "brand_entities_title" => [{"key" => "Big Yellow", "mentions" => 7, "ai_search_volume" => 70}]
        }
      }]
    end

    it "composes the domain and every brand term into one target list" do
      client = FakeClient.new(described_class::PATH => response)
      subject = described_class.new(
        profile: profile("domain" => "acme.co.uk", "brand_terms" => "Acme\nAcme Storage"),
        client: client
      )
      subject.call

      _path, task = client.calls.last
      expect(task[:target]).to eq([
        {domain: "acme.co.uk", include_subdomains: true},
        {keyword: "Acme", match_type: "word_match"},
        {keyword: "Acme Storage", match_type: "word_match"}
      ])
    end

    it "sends a COUNTRY code, never the city that the SERP endpoints want" do
      client = FakeClient.new(described_class::PATH => response)
      subject = described_class.new(
        # Exactly the profile that produced `40501 Invalid Field:
        # 'location_name'` — the LLM Mentions corpus has no cities in it.
        profile: profile("domain" => "acme.co.uk", "brand_terms" => "Acme",
                         "location_name" => "Cardiff,Wales,United Kingdom", "language_code" => "en"),
        client: client
      )
      data = subject.call

      _path, task = client.calls.last
      expect(task[:location_code]).to eq(2826)
      expect(task).not_to have_key(:location_name)
      expect(data[:location]).to eq("United Kingdom")
      expect(data[:location_is_fallback]).to be(false)
    end

    it "says so when it had to fall back to the United States" do
      client = FakeClient.new(described_class::PATH => response)
      subject = described_class.new(
        profile: profile("domain" => "acme.co.uk", "location_name" => "Valletta,Malta"),
        client: client
      )
      data = subject.call

      expect(client.calls.last.last[:location_code]).to eq(2840)
      expect(data[:location_is_fallback]).to be(true)
      expect(data[:location_reason]).to eq("unsupported")
      expect(data[:location_requested]).to eq("Malta")
    end

    it "caps targets at the API's limit of ten" do
      client = FakeClient.new(described_class::PATH => response)
      subject = described_class.new(
        profile: profile("domain" => "acme.co.uk", "brand_terms" => (1..20).map { |i| "term#{i}" }),
        client: client
      )
      subject.call

      expect(client.calls.last.last[:target].length).to eq(10)
    end

    it "sorts each breakdown by mentions and drops blank keys" do
      subject = described_class.new(
        profile: profile("domain" => "acme.co.uk"),
        client: FakeClient.new(described_class::PATH => response)
      )

      data = subject.call

      expect(data[:mentions]).to eq(42)
      expect(data[:ai_search_volume]).to eq(900)
      expect(data[:cited_sources].map { |r| r[:key] }).to eq(["trustpilot.com", "yell.com"])
      expect(data[:platforms].first[:key]).to eq("chat_gpt")
    end

    it "totals zero rather than blowing up on an empty aggregate" do
      subject = described_class.new(
        profile: profile("domain" => "acme.co.uk"),
        client: FakeClient.new(described_class::PATH => [])
      )

      expect(subject.call[:mentions]).to eq(0)
    end
  end

  describe Reports::Definitions::AiKeywordDemand do
    def months(volumes)
      volumes.each_with_index.map do |volume, index|
        {"year" => 2026, "month" => index + 1, "ai_search_volume" => volume}
      end
    end

    it "computes the three-on-three trend and buckets the keywords" do
      response = [{"items" => [
        # 100,100,100 then 200,200,200 => +100%
        {"keyword" => "storage cardiff", "ai_search_volume" => 200,
         "ai_monthly_searches" => months([100, 100, 100, 200, 200, 200])},
        # 200,200,200 then 100,100,100 => -50%
        {"keyword" => "self storage", "ai_search_volume" => 100,
         "ai_monthly_searches" => months([200, 200, 200, 100, 100, 100])},
        {"keyword" => "caravan storage", "ai_search_volume" => 0, "ai_monthly_searches" => []}
      ]}]

      subject = described_class.new(
        profile: profile("tracked_keywords" => "storage cardiff\nself storage\ncaravan storage"),
        client: FakeClient.new(described_class::PATH => response)
      )

      data = subject.call

      expect(data[:total_volume]).to eq(300)
      expect(data[:rising]).to eq(["storage cardiff"])
      expect(data[:falling]).to eq(["self storage"])
      expect(data[:absent]).to eq(["caravan storage"])
      expect(data[:keywords].first[:change_pct]).to eq(100.0)
    end

    it "sends a country code too, resolved against its own locations list" do
      response = [{"items" => [
        {"keyword" => "a", "ai_search_volume" => 10, "ai_monthly_searches" => []}
      ]}]
      client = FakeClient.new(described_class::PATH => response)

      data = described_class.new(
        profile: profile("tracked_keywords" => "a", "location_name" => "Cardiff,Wales,United Kingdom"),
        client: client
      ).call

      task = client.calls.last.last
      expect(task[:location_code]).to eq(2826)
      expect(task).not_to have_key(:location_name)
      expect(data[:location]).to eq("United Kingdom")
    end

    it "reports nil change rather than a fake zero when history is too short" do
      response = [{"items" => [
        {"keyword" => "a", "ai_search_volume" => 10, "ai_monthly_searches" => months([1, 2, 3])}
      ]}]

      subject = described_class.new(
        profile: profile("tracked_keywords" => "a"),
        client: FakeClient.new(described_class::PATH => response)
      )

      expect(subject.call[:keywords].first[:change_pct]).to be_nil
    end

    it "orders the monthly series oldest first, the opposite of what the API sends" do
      response = [{"items" => [
        {"keyword" => "a", "ai_search_volume" => 10, "ai_monthly_searches" => [
          {"year" => 2026, "month" => 3, "ai_search_volume" => 30},
          {"year" => 2026, "month" => 1, "ai_search_volume" => 10},
          {"year" => 2026, "month" => 2, "ai_search_volume" => 20}
        ]}
      ]}]

      subject = described_class.new(
        profile: profile("tracked_keywords" => "a"),
        client: FakeClient.new(described_class::PATH => response)
      )

      expect(subject.call[:keywords].first[:months].map { |m| m[:volume] }).to eq([10, 20, 30])
    end
  end

  describe Reports::Definitions::RankedKeywords do
    let(:response) do
      [{
        "total_count" => 512,
        "metrics" => {
          "organic" => {"count" => 500, "etv" => 1234.56, "pos_1" => 2, "pos_2_3" => 3,
                        "pos_4_10" => 10, "pos_11_20" => 20, "is_up" => 4, "is_down" => 1,
                        "is_new" => 2, "is_lost" => 0},
          "local_pack" => nil
        },
        "items" => [
          {"keyword_data" => {"keyword" => "storage cardiff",
                              "keyword_info" => {"search_volume" => 900, "cpc" => 1.25, "competition_level" => "HIGH"}},
           "ranked_serp_element" => {"etv" => 120.5, "serp_item" => {"rank_group" => 2, "type" => "organic", "url" => "https://acme.co.uk/"}}},
          {"keyword_data" => {"keyword" => "self storage cardiff",
                              "keyword_info" => {"search_volume" => 400, "cpc" => nil, "competition_level" => nil}},
           "ranked_serp_element" => {"etv" => 10.0, "serp_item" => {"rank_group" => 12, "type" => "organic", "url" => "https://acme.co.uk/units"}}},
          {"keyword_data" => {"keyword" => "", "keyword_info" => {}}, "ranked_serp_element" => {}}
        ]
      }]
    end

    it "keeps striking-distance keywords and counts the top three" do
      subject = described_class.new(
        profile: profile("domain" => "acme.co.uk"),
        client: FakeClient.new(described_class::PATH => response)
      )

      data = subject.call

      expect(data[:total_count]).to eq(512)
      expect(data[:top_3]).to eq(1)
      expect(data[:striking_distance].map { |k| k[:keyword] }).to eq(["self storage cardiff"])
      # The blank-keyword row is dropped rather than rendered as an empty row.
      expect(data[:keywords].length).to eq(2)
      expect(data[:metrics]["organic"][:etv]).to eq(1234.56)
      expect(data[:metrics]).not_to have_key("local_pack")
    end

    it "sends a COUNTRY code — Labs is country-scoped, like the AI endpoints" do
      client = FakeClient.new(described_class::PATH => response)
      data = described_class.new(
        # The profile that produced `40501 Invalid Field: 'location_name'`
        # from Labs, after the same value was fixed for AI visibility.
        profile: profile("domain" => "acme.co.uk",
                         "location_name" => "Cardiff,Wales,United Kingdom"),
        client: client
      ).call

      _path, task = client.calls.last
      expect(task[:location_code]).to eq(2826)
      expect(task).not_to have_key(:location_name)
      expect(data[:location]).to eq("United Kingdom")
      expect(data[:location_is_fallback]).to be(false)
    end

    it "asks for map-pack and AI Overview placements, not just organic" do
      client = FakeClient.new(described_class::PATH => response)
      described_class.new(profile: profile("domain" => "acme.co.uk"), client: client).call

      expect(client.calls.last.last[:item_types]).to include("local_pack", "ai_overview_reference")
    end
  end

  describe Reports::Definitions::LocalRankings do
    # A resolvable city, so the location step passes and the SERP parsing
    # under test is what is exercised.
    def profile(data = {}, general = {})
      super({"location_name" => "Cardiff,Wales,United Kingdom"}.merge(data), general)
    end

    let(:pack) do
      [
        {"type" => "local_pack", "title" => "Big Yellow", "domain" => "bigyellow.co.uk", "cid" => "111"},
        {"type" => "local_pack", "title" => "Acme Storage", "domain" => "www.acme.co.uk", "cid" => "999",
         "rating" => {"value" => 4.7, "votes_count" => 88}},
        {"type" => "local_pack", "title" => "Safestore", "domain" => "safestore.co.uk", "cid" => "222"}
      ]
    end

    it "reads our map-pack slot, our organic position, and who else is in the pack" do
      response = [[{"items" => pack + [
        {"type" => "organic", "rank_group" => 5, "domain" => "other.co.uk", "url" => "https://other.co.uk"},
        {"type" => "organic", "rank_group" => 8, "domain" => "acme.co.uk", "url" => "https://acme.co.uk/units"}
      ], "se_results_count" => 1234}]]

      subject = described_class.new(
        profile: profile("domain" => "acme.co.uk", "tracked_keywords" => "storage cardiff"),
        client: FakeClient.new(described_class::PATH => response)
      )

      data = subject.call
      row = data[:keywords].first

      expect(row[:local_pack_position]).to eq(2)
      expect(row[:organic_position]).to eq(8)
      expect(row[:rating]).to eq(4.7)
      expect(data[:in_map_pack]).to eq(1)
      expect(data[:map_pack_rivals].map { |r| r[:title] }).to contain_exactly("Big Yellow", "Safestore")
    end

    it "matches on CID when the listing points at a different domain" do
      response = [[{"items" => [
        {"type" => "local_pack", "title" => "Acme Storage", "domain" => "book.acmestorage.io", "cid" => "999"}
      ]}]]

      subject = described_class.new(
        profile: profile("domain" => "acme.co.uk", "cid" => "999", "tracked_keywords" => "storage cardiff"),
        client: FakeClient.new(described_class::PATH => response)
      )

      expect(subject.call[:keywords].first[:local_pack_position]).to eq(1)
    end

    it "records a per-keyword error instead of failing the whole report" do
      subject = described_class.new(
        profile: profile("domain" => "acme.co.uk", "tracked_keywords" => "a\nb"),
        client: FakeClient.new(described_class::PATH => [nil, [{"items" => []}]])
      )

      data = subject.call

      expect(data[:keywords].first[:error]).to be_present
      # The same shape as a good row: the page reads `local_pack.length` on
      # every row and a bare `{keyword, error}` blew it up.
      expect(data[:keywords].first).to include(local_pack: [], organic_position: nil, local_pack_position: nil, has_ai_overview: false)
      expect(data[:keywords].last[:error]).to be_nil
      expect(data[:not_ranking]).to eq(["b"])
    end

    it "asks on mobile, because local intent is phone-first" do
      client = FakeClient.new(described_class::PATH => [[{"items" => []}]])
      described_class.new(
        profile: profile("domain" => "acme.co.uk", "tracked_keywords" => "a"),
        client: client
      ).call

      expect(client.calls.last.last.first[:device]).to eq("mobile")
    end
  end

  describe Reports::Definitions::BusinessProfile do
    def profile(data = {}, general = {})
      super({"location_name" => "Cardiff,Wales,United Kingdom"}.merge(data), general)
    end

    let(:listing) do
      {"title" => "Acme Storage", "category" => "Self-storage facility",
       "additional_categories" => ["Moving company"], "address" => "1 High St",
       "phone" => "+44 29 0000 0000", "url" => "https://acme.co.uk", "domain" => "acme.co.uk",
       "description" => "A" * 200, "rating" => {"value" => 4.6, "votes_count" => 120},
       "total_photos" => 40, "work_time" => {"current_status" => "open", "work_hours" => {"timetable" => {}}},
       "services" => [{"title" => "Storage"}], "place_topics" => {"clean" => 12}}
    end

    it "flags nothing on a complete listing" do
      subject = described_class.new(
        profile: profile("business_name" => "Acme Storage", "domain" => "acme.co.uk"),
        client: FakeClient.new(described_class::PATH => [{"items" => [listing]}])
      )

      data = subject.call

      expect(data[:found]).to be(true)
      expect(data[:rating]).to eq(4.6)
      expect(data[:issues]).to be_empty
    end

    it "flags the gaps that cost map-pack visibility" do
      bare = listing.merge(
        "phone" => "", "description" => "", "additional_categories" => [],
        "total_photos" => 2, "rating" => {"value" => 3.2, "votes_count" => 4},
        "work_time" => {"current_status" => "temporarily_closed", "work_hours" => nil},
        "services" => []
      )

      subject = described_class.new(
        profile: profile("business_name" => "Acme Storage", "domain" => "acme.co.uk"),
        client: FakeClient.new(described_class::PATH => [{"items" => [bare]}])
      )

      messages = subject.call[:issues].map { |i| i[:message] }

      expect(messages).to include(
        a_string_matching(/temporarily closed/),
        a_string_matching(/No phone number/),
        a_string_matching(/No description/),
        a_string_matching(/No secondary categories/),
        a_string_matching(/Opening hours not set/),
        a_string_matching(/Rating is 3.2/),
        a_string_matching(/No services listed/)
      )
    end

    it "flags a listing pointing at the wrong site" do
      subject = described_class.new(
        profile: profile("business_name" => "Acme Storage", "domain" => "acme.co.uk"),
        client: FakeClient.new(described_class::PATH => [{"items" => [listing.merge("domain" => "old-acme.co.uk")]}])
      )

      expect(subject.call[:issues].map { |i| i[:message] })
        .to include(a_string_matching(/points at old-acme\.co\.uk/))
    end

    it "prefers an exact place_id over searching by name" do
      client = FakeClient.new(described_class::PATH => [{"items" => [listing]}])
      described_class.new(
        profile: profile("business_name" => "Acme Storage", "place_id" => "ChIJabc"),
        client: client
      ).call

      task = client.calls.last.last
      expect(task[:place_id]).to eq("ChIJabc")
      expect(task).not_to have_key(:keyword)
    end

    it "says so plainly when there is no listing at all" do
      subject = described_class.new(
        profile: profile("business_name" => "Nowhere Ltd"),
        client: FakeClient.new(described_class::PATH => [{"items" => []}])
      )

      data = subject.call
      expect(data[:found]).to be(false)
      expect(data[:searched_for]).to eq("Nowhere Ltd")
    end
  end

  describe Reports::Definitions::PageHealth do
    def page(checks:, url: "https://acme.co.uk/", score: 88.4)
      [{"items" => [{
        "url" => url, "status_code" => 200, "onpage_score" => score,
        "meta" => {"title" => "Acme", "title_length" => 4, "description" => "d",
                   "description_length" => 1, "htags" => {"h1" => ["Acme"]},
                   "internal_links_count" => 10, "images_count" => 3,
                   "cumulative_layout_shift" => 0.02},
        "page_timing" => {"largest_contentful_paint" => 1800, "waiting_time" => 120},
        "size" => 204_800, "checks" => checks, "resource_errors" => {"errors" => []}
      }]}]
    end

    it "translates the checks that matter into sentences, worst first" do
      subject = described_class.new(
        profile: profile({}, "site_base_url" => "https://acme.co.uk"),
        client: FakeClient.new(described_class::PATH => [page(checks: {
          "no_title" => true, "no_image_alt" => true, "no_favicon" => true,
          "is_https" => true, "high_loading_time" => false
        })])
      )

      issues = subject.call[:pages].first[:issues]

      expect(issues.map { |i| i[:severity] }).to eq(%w[critical medium low])
      expect(issues.first[:message]).to eq("No title tag")
    end

    it "treats the inverted checks correctly — false on has_micromarkup is the problem" do
      subject = described_class.new(
        profile: profile({}, "site_base_url" => "https://acme.co.uk"),
        client: FakeClient.new(described_class::PATH => [page(checks: {"has_micromarkup" => false})])
      )

      expect(subject.call[:pages].first[:issues].map { |i| i[:message] })
        .to eq(["No structured data (schema.org)"])
    end

    it "separates a template problem from a one-page one" do
      responses = [
        page(checks: {"no_h1_tag" => true, "no_title" => true}, url: "https://acme.co.uk/a"),
        page(checks: {"no_h1_tag" => true}, url: "https://acme.co.uk/b")
      ]

      subject = described_class.new(
        profile: profile("audit_urls" => "https://acme.co.uk/a\nhttps://acme.co.uk/b"),
        client: FakeClient.new(described_class::PATH => responses)
      )

      data = subject.call

      expect(data[:recurring_issues].map { |i| i[:check] }).to eq(["no_h1_tag"])
      expect(data[:recurring_issues].first[:pages]).to eq(2)
    end

    it "leads with the page that would not crawl, then the worst score, and averages only what did" do
      responses = [
        page(checks: {}, url: "https://acme.co.uk/a", score: 90.0),
        nil,
        page(checks: {}, url: "https://acme.co.uk/c", score: 50.0)
      ]

      subject = described_class.new(
        profile: profile("audit_urls" => "https://acme.co.uk/a\nhttps://acme.co.uk/b\nhttps://acme.co.uk/c"),
        client: FakeClient.new(described_class::PATH => responses)
      )

      data = subject.call

      # An uncrawlable page has no score, so it sorts ahead of every scored
      # one — which is right: it is the most urgent thing on the list.
      expect(data[:pages].map { |p| p[:url] })
        .to eq(["https://acme.co.uk/b", "https://acme.co.uk/c", "https://acme.co.uk/a"])
      expect(data[:pages].first[:error]).to be_present
      expect(data[:average_score]).to eq(70.0)
    end
  end

  describe "the city reports" do
    it "send the CITY as a code, resolved against the endpoint's own list — never as a name" do
      # The value that produced `40501 Invalid Field: 'location_name'` from
      # Business Data, after the same fix had been applied to two other
      # endpoints. Codes are unambiguous; names are a negotiation.
      response = [[{"items" => []}]]
      client = FakeClient.new(Reports::Definitions::LocalRankings::PATH => response)

      data = Reports::Definitions::LocalRankings.new(
        profile: profile("domain" => "acme.co.uk", "tracked_keywords" => "a",
                         "location_name" => "Cardiff, Wales, United Kingdom"),
        client: client
      ).call

      task = client.calls.last.last.first
      expect(task[:location_code]).to eq(1_006_886)
      expect(task).not_to have_key(:location_name)
      expect(data[:location]).to eq("Cardiff,Wales,United Kingdom")
      # It looked in the SERP list for GB, not the Business Data one.
      expect(client.calls.map(&:first)).to include("serp/google/locations/gb")
    end

    it "Business profile resolves against Business Data's list" do
      client = FakeClient.new(Reports::Definitions::BusinessProfile::PATH => [{"items" => []}])
      Reports::Definitions::BusinessProfile.new(
        profile: profile("business_name" => "Acme", "location_name" => "Cardiff,Wales,United Kingdom"),
        client: client
      ).call

      expect(client.calls.map(&:first)).to include("business_data/google/locations/gb")
      expect(client.calls.last.last[:location_code]).to eq(1_006_886)
    end

    it "fail with the fix rather than running against the wrong place" do
      client = FakeClient.new(Reports::Definitions::LocalRankings::PATH => [[{"items" => []}]])
      subject = Reports::Definitions::LocalRankings.new(
        profile: profile("domain" => "acme.co.uk", "tracked_keywords" => "a", "location_name" => "Atlantis,United Kingdom"),
        client: client
      )

      expect { subject.call }.to raise_error(DataForSeo::Error, /Couldn't match "Atlantis,United Kingdom".*Settings/)
      # And spent nothing finding out.
      expect(client.calls.map(&:first)).not_to include(Reports::Definitions::LocalRankings::PATH)
    end

    it "name the missing location when none is set" do
      client = FakeClient.new(Reports::Definitions::BusinessProfile::PATH => [{"items" => []}])
      subject = Reports::Definitions::BusinessProfile.new(profile: profile("business_name" => "Acme"), client: client)

      expect { subject.call }.to raise_error(DataForSeo::Error, /No location is set.*Cardiff,Wales,United Kingdom/)
    end

    it "send no location at all for a crawl" do
      client = FakeClient.new(Reports::Definitions::PageHealth::PATH => [[{"items" => []}]])

      Reports::Definitions::PageHealth.new(
        profile: profile("audit_urls" => "https://acme.co.uk/"),
        client: client
      ).call

      task = client.calls.last.last.first
      expect(task).not_to have_key(:location_name)
      expect(task).not_to have_key(:location_code)
      expect(task).not_to have_key(:language_code)
    end
  end

  describe "the catalog" do
    it "has every report declare its granularity, and name a list when it needs one" do
      Reports::Catalog.all.each do |definition|
        expect(%i[city country none]).to include(definition.location_granularity), definition.key
        if definition.location_granularity == :country
          expect(DataForSeo::Locations::APIS).to have_key(definition.locations_api), definition.key
        end
      end
    end
  end
end

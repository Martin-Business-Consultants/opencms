# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sitemap", type: :request do
  let(:user) { create(:user) }

  def make_page(attrs = {})
    Page.create!({
      slug:        "p-#{SecureRandom.hex(3)}",
      title:       "A page",
      status:      "published",
      locale:      "en",
      blocks:      [],
      schema:      {"fields" => []},
      frontmatter: {},
      seo:         {}
    }.merge(attrs))
  end

  describe "GET /sitemap" do
    it "redirects unauthenticated visitors to sign-in" do
      get sitemap_url
      expect(response).to redirect_to(sign_in_url)
    end

    it "renders the admin tree for signed-in users" do
      sign_in_as user
      make_page(slug: "about")

      get sitemap_url
      expect(response).to have_http_status(:success)
      body = response.body.gsub(/\s+/, " ")
      expect(body).to include("/about", %(Included <span class="count">(1)</span>))
      # A row links to its editor and quick-edits its sitemap settings in place.
      expect(body).to include(edit_page_path("about"), "Quick edit")
    end

    it "never turns an author's non-http canonical URL into a link" do
      sign_in_as user
      make_page(slug: "sneaky", seo: {"canonical_url" => "javascript:alert(1)"})

      get sitemap_url
      expect(response.body).not_to include(%(href="javascript:))
    end

    it "lists what the sitemap leaves out under Excluded" do
      sign_in_as user
      make_page(slug: "kept")
      make_page(slug: "hidden", status: "draft")

      get sitemap_url(show: "excluded")
      expect(response.body).to include("/hidden")
      expect(response.body).not_to include("/kept")
    end
  end

  describe "PATCH /sitemap/:source/:id" do
    let(:page) { make_page(slug: "patchable", status: "draft", seo: {"meta_title" => "keep me"}) }

    before { sign_in_as user }

    it "401-style redirects unauthenticated callers" do
      sign_out
      patch sitemap_entry_url("page", page.id), params: {entry: {status: "published"}}
      expect(response).to redirect_to(sign_in_url)
    end

    it "updates status and merges sitemap fields into seo" do
      patch sitemap_entry_url("page", page.id),
        params: {entry: {
          status:             "published",
          sitemap_priority:   "0.9",
          sitemap_changefreq: "daily",
          noindex:            "true",
          nofollow:           "false"
        }}

      expect(response).to redirect_to(sitemap_path)
      page.reload
      expect(page.status).to eq("published")
      expect(page.seo["sitemap_priority"]).to eq(0.9)
      expect(page.seo["sitemap_changefreq"]).to eq("daily")
      expect(page.seo["noindex"]).to eq(true)
      expect(page.seo["nofollow"]).to eq(false)
      expect(page.seo["meta_title"]).to eq("keep me")
    end

    it "clamps priority into 0.0..1.0" do
      patch sitemap_entry_url("page", page.id), params: {entry: {sitemap_priority: "5"}}
      expect(page.reload.seo["sitemap_priority"]).to eq(1.0)
    end

    it "clears a sitemap field when blank" do
      page.update!(seo: page.seo.merge("sitemap_priority" => 0.9))
      patch sitemap_entry_url("page", page.id), params: {entry: {sitemap_priority: ""}}
      expect(page.reload.seo).not_to have_key("sitemap_priority")
    end

    it "ignores invalid changefreq" do
      patch sitemap_entry_url("page", page.id), params: {entry: {sitemap_changefreq: "bogus"}}
      expect(page.reload.seo).not_to have_key("sitemap_changefreq")
    end

    it "updates a CollectionEntry" do
      coll = Collection.create!(slug: "blog", name: "Blog", schema: {"fields" => []})
      entry = CollectionEntry.create!(
        collection: coll, slug: "post", title: "Post", status: "draft", locale: "en",
        frontmatter: {}, body_markdown: "", seo: {}
      )

      patch sitemap_entry_url("collection_entry", entry.id),
        params: {entry: {status: "published", sitemap_priority: "0.4"}}

      expect(response).to redirect_to(sitemap_path)
      entry.reload
      expect(entry.status).to eq("published")
      expect(entry.seo["sitemap_priority"]).to eq(0.4)
    end

    it "rejects unknown sources via the route constraint" do
      patch "/sitemap/global/1", params: {entry: {status: "published"}}
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /sitemap.xml" do
    before { make_page(slug: "about") }

    it "returns XML without authentication" do
      get "/sitemap.xml"
      expect(response).to have_http_status(:success)
      expect(response.media_type).to start_with("application/xml")
      expect(response.body).to include("<urlset")
      expect(response.body).to include("<loc>")
      expect(response.body).to match(%r{/about</loc>})
    end

    it "uses the configured site_base_url for absolute URLs" do
      Setting.set("general", site_base_url: "https://www.example.org")

      get "/sitemap.xml"
      expect(response.body).to include("<loc>https://www.example.org/about</loc>")
    end

    it "excludes drafts and noindex pages" do
      make_page(slug: "drafty", status: "draft")
      make_page(slug: "hidden", seo: {"noindex" => true})

      get "/sitemap.xml"
      expect(response.body).not_to include("/drafty")
      expect(response.body).not_to include("/hidden")
    end
  end
end

# Changing a row's status publishes or unpublishes it, so from the sitemap it
# takes the publish capability, as the page and entry editors do; sitemap
# settings alone need only write.
RSpec.describe "Sitemap status changes", type: :request do
  let(:writer) { create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write])) }
  let(:draft) { Page.create!(slug: "draft-one", title: "Draft", status: "draft", locale: "en", blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {}) }

  it "refuses a writer's status change in the admin and saves nothing" do
    sign_in_as writer

    patch sitemap_entry_path("page", draft.id), params: {entry: {status: "published", sitemap_priority: "0.9"}}

    expect(flash[:alert]).to match(/permission to publish/)
    expect(draft.reload).to have_attributes(status: "draft", seo: {})
  end

  it "still saves a writer's sitemap settings when the status stays" do
    sign_in_as writer

    patch sitemap_entry_path("page", draft.id), params: {entry: {status: "draft", sitemap_priority: "0.9"}}

    expect(draft.reload.status).to eq("draft")
    expect(draft.seo["sitemap_priority"]).to eq(0.9)
  end

  it "hides the status field from a writer's Quick edit" do
    sign_in_as writer
    draft

    get sitemap_path

    expect(response.body).to include("Quick edit")
    expect(response.body).not_to include(%(name="entry[status]"))
  end

  it "answers 403 to an API status change without pages:publish, and saves nothing" do
    token = writer.api_token.token

    patch "/api/sitemap/page/#{draft.id}", params: {entry: {status: "published"}},
      headers: {"Authorization" => "Bearer #{token}"}, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to include("capability" => "pages:publish")
    expect(draft.reload.status).to eq("draft")
  end
end

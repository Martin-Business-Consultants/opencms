# frozen_string_literal: true

require "rails_helper"

# Covers the endpoints added so the API and the `cms` CLI can do what the admin
# UI does. The point of each example is one of:
#
#   * the endpoint exists and returns the shape the CLI parses,
#   * the capability gate is real, not decorative, and
#   * the destructive paths behave the way the docs promise (delete means
#     trash, not oblivion).
RSpec.describe "Api parity surface", type: :request do
  let(:admin) { create(:user) }

  # A token is exactly as capable as its owner's role, so "a token with these
  # capabilities" means a user whose role holds exactly them.
  def auth(capabilities = nil)
    actor = capabilities ? create(:user, admin: false, role: create(:role, permissions: capabilities)) : admin
    {"Authorization" => "Bearer #{actor.api_token.token}"}
  end

  def json = JSON.parse(response.body)

  def make_page(slug: "about", **attrs)
    Page.create!({slug: slug, title: slug.titleize, status: "draft", locale: "en"}.merge(attrs))
  end

  def make_collection(slug: "posts", fields: [])
    Collection.create!(slug: slug, name: slug.titleize, schema: {"fields" => fields})
  end

  # ---- Trash -------------------------------------------------------------

  describe "trash" do
    it "sends a deleted page to the trash rather than destroying it" do
      page = make_page

      delete "/api/pages/about", headers: auth
      expect(response).to have_http_status(:no_content)

      expect(Page.find_by(slug: "about")).to be_nil
      expect(Page.with_discarded.find(page.id)).to be_present
    end

    it "lists what's recoverable and restores it" do
      page = make_page
      page.discard!

      get "/api/trash", headers: auth(["trash:read"])
      expect(response).to have_http_status(:success)
      expect(json["entries"].map { |e| e["id"] }).to include(page.id)
      expect(json["counts"]["page"]).to eq(1)

      post "/api/trash/page/#{page.id}/restore", headers: auth(["trash:write"])
      expect(response).to have_http_status(:success)
      expect(Page.find_by(slug: "about")).to be_present
    end

    it "names the valid kinds instead of 500ing on a bad one" do
      post "/api/trash/wombat/1/restore", headers: auth(["trash:write"])

      expect(response).to have_http_status(:not_found)
      expect(json["message"]).to include("page")
    end

    it "requires trash:write to purge, not merely trash:read" do
      page = make_page
      page.discard!

      delete "/api/trash/page/#{page.id}", headers: auth(["trash:read"])
      expect(response).to have_http_status(:forbidden)
    end

    it "purges permanently when asked to" do
      page = make_page
      page.discard!

      delete "/api/trash/page/#{page.id}", headers: auth(["trash:write"])
      expect(response).to have_http_status(:no_content)
      expect(Page.with_discarded.find_by(id: page.id)).to be_nil
    end
  end

  # ---- Bulk operations ---------------------------------------------------

  describe "bulk operations" do
    it "publishes several pages by path and reports the ones it couldn't find" do
      make_page(slug: "about")
      make_page(slug: "pricing")

      post "/api/pages/bulk_update_status",
        params: {status: "published", paths: %w[about pricing ghost]},
        headers: auth, as: :json

      expect(response).to have_http_status(:success)
      expect(json["updated"]).to eq(2)
      expect(json["not_found"]).to eq(["ghost"])
      expect(Page.where(status: "published").count).to eq(2)
    end

    it "rejects a status that isn't one of the known ones" do
      post "/api/pages/bulk_update_status",
        params: {status: "sideways", paths: ["about"]},
        headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["message"]).to include("draft")
    end

    it "gates bulk publish behind pages:publish, not pages:write" do
      make_page

      post "/api/pages/bulk_update_status",
        params: {status: "published", paths: ["about"]},
        headers: auth(["pages:read", "pages:write"]), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json["capability"]).to eq("pages:publish")
    end

    it "bulk-deletes to the trash" do
      make_page(slug: "about")

      post "/api/pages/bulk_destroy", params: {paths: ["about"]}, headers: auth, as: :json

      expect(json["deleted"]).to eq(1)
      expect(Page.find_by(slug: "about")).to be_nil
      expect(Page.discarded.count).to eq(1)
    end
  end

  # ---- Schema editing ----------------------------------------------------

  describe "schema editing" do
    it "replaces a page's field schema" do
      make_page

      patch "/api/pages/about/schema",
        params: {page: {fields: [{"name" => "note", "label" => "Note", "type" => "string"}]}},
        headers: auth, as: :json

      expect(response).to have_http_status(:success)
      expect(Page.find_by!(slug: "about").schema["fields"].first["name"]).to eq("note")
    end

    # The page slug is a full path and may contain slashes, so this route has
    # to be matched ahead of `PATCH /api/pages/:slug` or the update action
    # swallows it with slug="about/schema".
    it "reaches the schema of a nested page" do
      parent = make_page(slug: "about")
      Page.create!(slug: "team", title: "Team", status: "draft", locale: "en", parent_id: parent.id)

      patch "/api/pages/about/team/schema",
        params: {page: {fields: [{"name" => "role", "label" => "Role", "type" => "string"}]}},
        headers: auth, as: :json

      expect(response).to have_http_status(:success)
      expect(json["page"]["path"]).to eq("about/team")
      expect(Page.find_by!(path: "about/team").schema["fields"].first["name"]).to eq("role")
    end

    it "refuses a collection schema sent without its collection key, leaving the schema alone" do
      collection = make_collection(fields: [{"name" => "title", "type" => "text"}])

      patch "/api/collections/posts/schema", params: {fields: [{"name" => "x", "type" => "text"}]}, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid")
      expect(json["errors"]).to have_key("collection")
      expect(collection.reload.fields.map { it["name"] }).to eq(["title"])
    end

    it "replaces a collection's field schema and keeps its other settings" do
      make_collection

      patch "/api/collections/posts/schema",
        params: {collection: {
          fields:        [{"name" => "featured", "label" => "Featured", "type" => "boolean"}],
          enable_blocks: true
        }},
        headers: auth, as: :json

      expect(response).to have_http_status(:success)
      collection = Collection.find_by!(slug: "posts")
      expect(collection.fields.first["name"]).to eq("featured")
      expect(collection.enable_blocks).to be(true)
    end

    it "requires collections:write" do
      make_collection

      patch "/api/collections/posts/schema",
        params: {collection: {fields: []}},
        headers: auth(["collections:read"]), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    # The Build board's column config travels with the schema, so the CLI can
    # set up a board without the admin UI.
    it "stores a build config posted alongside the fields" do
      make_collection

      patch "/api/collections/posts/schema",
        params: {collection: {
          fields:       [{"name" => "active", "type" => "boolean"}],
          build_config: {field: "active", on_label: "Live"}
        }},
        headers: auth, as: :json

      expect(response).to have_http_status(:success)
      expect(json.dig("collection", "build_config"))
        .to eq("field" => "active", "on_label" => "Live", "card_fields" => [])
    end
  end

  # ---- Entry toggles -----------------------------------------------------

  describe "entry toggle_field" do
    let!(:collection) do
      make_collection(fields: [
        {"name" => "featured", "label" => "Featured", "type" => "boolean"},
        {"name" => "summary",  "label" => "Summary",  "type" => "string"}
      ])
    end

    # The whole reason this endpoint exists instead of a PATCH: it merges one
    # key rather than replacing the frontmatter blob.
    it "flips one boolean without disturbing the rest of the frontmatter" do
      collection.entries.create!(
        slug: "hello", title: "Hello", status: "draft",
        frontmatter: {"summary" => "kept", "featured" => false}
      )

      patch "/api/collections/posts/entries/hello/toggle_field",
        params: {field: "featured", value: true}, headers: auth, as: :json

      expect(response).to have_http_status(:success)
      frontmatter = collection.entries.find_by!(slug: "hello").frontmatter
      expect(frontmatter["featured"]).to be(true)
      expect(frontmatter["summary"]).to eq("kept")
    end

    it "explains which fields are toggleable when given a bad one" do
      collection.entries.create!(slug: "hello", title: "Hello", status: "draft")

      patch "/api/collections/posts/entries/hello/toggle_field",
        params: {field: "summary", value: true}, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["boolean_fields"]).to eq(["featured"])
    end
  end

  # ---- Entry inline field writes ----------------------------------------

  describe "entry update_field" do
    let!(:collection) do
      make_collection(fields: [
        {"name" => "active", "type" => "boolean"},
        {"name" => "day", "type" => "select", "options" => %w[Monday Tuesday]},
        {"name" => "notes", "type" => "text"}
      ])
    end

    # Same one-key merge as toggle_field, widened to the scalars a Build card
    # can carry.
    it "merges one non-boolean key without disturbing the rest" do
      collection.entries.create!(
        slug: "hello", title: "Hello", status: "draft",
        frontmatter: {"active" => true, "day" => "Monday"}
      )

      patch "/api/collections/posts/entries/hello/update_field",
        params: {field: "day", value: "Tuesday"}, headers: auth, as: :json

      expect(response).to have_http_status(:success)
      frontmatter = collection.entries.find_by!(slug: "hello").frontmatter
      expect(frontmatter["day"]).to eq("Tuesday")
      expect(frontmatter["active"]).to be(true)
    end

    it "names the editable fields when given one that isn't" do
      collection.entries.create!(slug: "hello", title: "Hello", status: "draft")

      patch "/api/collections/posts/entries/hello/update_field",
        params: {field: "notes", value: "x"}, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["inline_fields"]).to eq(%w[active day])
    end
  end

  # ---- Entry board moves -------------------------------------------------

  describe "entry move" do
    let!(:collection) do
      c = make_collection(fields: [
        {"name" => "active", "type" => "boolean"},
        {"name" => "featured", "type" => "boolean"}
      ])
      c.update!(build_config: {"field" => "active", "also_fields" => ["featured"], "also_publish" => true})
      c
    end

    before { collection.entries.create!(slug: "hello", title: "Hello", status: "draft") }

    # The board's drag, over the wire: one call moves everything the column
    # stands for, so the CLI can't leave an entry half-moved.
    it "turns on everything the right-hand column means" do
      patch "/api/collections/posts/entries/hello/move",
        params: {on: true}, headers: auth, as: :json

      expect(response).to have_http_status(:success)
      entry = collection.entries.find_by!(slug: "hello")
      expect(entry.frontmatter).to include("active" => true, "featured" => true)
      expect(entry.status).to eq "published"
    end

    it "mirrors it back off" do
      patch "/api/collections/posts/entries/hello/move",
        params: {on: true}, headers: auth, as: :json
      patch "/api/collections/posts/entries/hello/move",
        params: {on: false}, headers: auth, as: :json

      entry = collection.entries.find_by!(slug: "hello")
      expect(entry.frontmatter).to include("active" => false, "featured" => false)
      expect(entry.status).to eq "draft"
    end

    # Writing frontmatter is `entries:write`; putting something in front of
    # visitors is not.
    it "refuses a publishing board without entries:publish" do
      patch "/api/collections/posts/entries/hello/move",
        params: {on: true}, headers: auth(%w[entries:read entries:write]), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(collection.entries.find_by!(slug: "hello").status).to eq "draft"
    end

    it "says so when the collection has no board" do
      collection.update!(build_config: {})

      patch "/api/collections/posts/entries/hello/move",
        params: {on: true}, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["message"]).to match(/no Build board/)
    end
  end

  # ---- Redirects ---------------------------------------------------------

  describe "redirects" do
    it "keeps the edge-facing payload shape on the unauthenticated-role read" do
      Redirect.create!(source_path: "/old", destination_url: "/new", status_code: 301, active: true)

      get "/api/redirects", headers: auth(["pages:read"])

      expect(response).to have_http_status(:success)
      expect(json["redirects"].first).to eq(
        "source" => "/old", "destination" => "/new", "status" => 301, "wildcard" => false
      )
    end

    it "creates a rule" do
      post "/api/redirects",
        params: {redirect: {source_path: "/old", destination_url: "/new", status_code: 301}},
        headers: auth(["redirects:write"]), as: :json

      expect(response).to have_http_status(:created)
      expect(Redirect.find_by(source_path: "/old")).to be_present
    end

    it "refuses to create without redirects:write" do
      post "/api/redirects",
        params: {redirect: {source_path: "/old", destination_url: "/new"}},
        headers: auth(["redirects:read"]), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "round-trips CSV: what export emits, import accepts" do
      Redirect.create!(source_path: "/old", destination_url: "/new", status_code: 301, active: true)

      get "/api/redirects/export", headers: auth(["redirects:read"])
      expect(response).to have_http_status(:success)
      csv = response.body
      expect(csv).to include("/old,/new,301")

      Redirect.delete_all
      post "/api/redirects/import", params: csv, headers: auth(["redirects:write"]).merge("CONTENT_TYPE" => "text/csv")

      expect(response).to have_http_status(:success)
      expect(json["created"]).to eq(1)
      expect(Redirect.find_by(source_path: "/old").destination_url).to eq("/new")
    end

    it "upserts on import rather than duplicating" do
      Redirect.create!(source_path: "/old", destination_url: "/stale", status_code: 301, active: true)
      csv = "source_path,destination_url,status_code,active,notes\n/old,/fresh,301,true,\n"

      post "/api/redirects/import", params: csv, headers: auth(["redirects:write"]).merge("CONTENT_TYPE" => "text/csv")

      expect(json).to include("created" => 0, "updated" => 1)
      expect(Redirect.where(source_path: "/old").count).to eq(1)
      expect(Redirect.find_by(source_path: "/old").destination_url).to eq("/fresh")
    end
  end

  # ---- Submissions -------------------------------------------------------

  describe "submissions" do
    let!(:form) do
      Form.create!(slug: "contact", title: "Contact", status: "published",
                   fields: [{"name" => "email", "label" => "Email", "type" => "email"}])
    end

    it "lists submissions across forms, and filters to one" do
      form.submissions.create!(data: {"email" => "a@b.com"}, ip: "127.0.0.1")

      get "/api/submissions", headers: auth(["submissions:read"])
      expect(response).to have_http_status(:success)
      expect(json["total"]).to eq(1)
      expect(json["submissions"].first["preview"]).to eq("a@b.com")

      get "/api/forms/contact/submissions", headers: auth(["submissions:read"])
      expect(json["total"]).to eq(1)
    end

    it "returns the full data on show" do
      submission = form.submissions.create!(data: {"email" => "a@b.com"}, ip: "127.0.0.1")

      get "/api/submissions/#{submission.id}", headers: auth(["submissions:read"])

      expect(json["submission"]["data"]).to eq("email" => "a@b.com")
    end

    it "needs submissions:delete to delete" do
      submission = form.submissions.create!(data: {"email" => "a@b.com"}, ip: "127.0.0.1")

      delete "/api/submissions/#{submission.id}", headers: auth(["submissions:read"])
      expect(response).to have_http_status(:forbidden)

      delete "/api/submissions/#{submission.id}", headers: auth(["submissions:read", "submissions:delete"])
      expect(response).to have_http_status(:no_content)
      expect(FormSubmission.count).to eq(0)
    end

    it "exposes the form's email templates with the tokens they accept" do
      get "/api/forms/contact/emails", headers: auth(["forms:read"])

      expect(response).to have_http_status(:success)
      expect(json["emails"].map { |e| e["kind"] }).to match_array(%w[notification confirmation])
      expect(json["available_tokens"]).to include("email", "form_title", "submitted_at")
    end

    it "updates one template" do
      patch "/api/forms/contact/emails/notification",
        params: {form_email: {enabled: true, subject: "New: {{form_title}}",
                              body: "From {{email}}", recipients: "ops@example.com"}},
        headers: auth(["forms:read", "forms:write"]), as: :json

      expect(response).to have_http_status(:success)
      expect(json["email"]["subject"]).to eq("New: {{form_title}}")
      expect(form.emails.find_by(kind: "notification").enabled).to be(true)
    end
  end

  # ---- Webhooks ----------------------------------------------------------

  describe "webhooks" do
    let!(:webhook) do
      Webhook.create!(name: "Build", url: "https://example.com/hook", events: ["page.published"])
    end

    it "lists without the secret and shows with it" do
      get "/api/webhooks", headers: auth(["webhooks:read"])
      expect(json["webhooks"].first).not_to have_key("secret")

      get "/api/webhooks/#{webhook.id}", headers: auth(["webhooks:read"])
      expect(json["webhook"]["secret"]).to be_present
    end

    it "rotates the signing secret" do
      before_secret = webhook.secret

      post "/api/webhooks/#{webhook.id}/rotate_secret", headers: auth(["webhooks:write"])

      expect(response).to have_http_status(:success)
      expect(webhook.reload.secret).not_to eq(before_secret)
    end

    it "enqueues a test delivery and says so, rather than claiming it was sent" do
      expect {
        post "/api/webhooks/#{webhook.id}/test", headers: auth(["webhooks:write"])
      }.to have_enqueued_job(Webhook::DeliveryJob)

      expect(response).to have_http_status(:accepted)
      expect(json).to include("enqueued" => true)
    end

    it "gates writes" do
      post "/api/webhooks/#{webhook.id}/rotate_secret", headers: auth(["webhooks:read"])
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---- Review requests ---------------------------------------------------

  describe "review requests" do
    let!(:page) { make_page }

    it "lets a writer open a review and a publisher approve it, publishing the page" do
      post "/api/review_requests",
        params: {reviewable_type: "Page", slug: "about", comment: "ready"},
        headers: auth(["pages:read", "pages:write"]), as: :json

      expect(response).to have_http_status(:created)
      expect(json["review_request"]["state"]).to eq("pending")
      review_id = json["review_request"]["id"]

      post "/api/review_requests/#{review_id}/approve", headers: auth, as: :json

      expect(response).to have_http_status(:success)
      expect(json["review_request"]["state"]).to eq("approved")
      expect(page.reload.status).to eq("published")
    end

    # Approving publishes, so it takes the capability publishing takes.
    it "won't let a writer approve their own request" do
      review = page.review_requests.create!(requested_by: admin)

      post "/api/review_requests/#{review.id}/approve",
        headers: auth(["pages:read", "pages:write"]), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json["capability"]).to eq("pages:publish")
    end

    it "409s on a second decision rather than silently overwriting the first" do
      review = page.review_requests.create!(requested_by: admin)
      review.approve!(by: admin)

      post "/api/review_requests/#{review.id}/request_changes", headers: auth, as: :json

      expect(response).to have_http_status(:conflict)
    end
  end

  # ---- Audit log ---------------------------------------------------------

  describe "audit log" do
    it "filters by action and actor" do
      AuditLog.record(action: "page.published", actor: admin, target: make_page)
      AuditLog.record(action: "page.deleted",   actor: admin)

      get "/api/audit_log", params: {event: "page.published"}, headers: auth(["audit_log:read"])

      expect(response).to have_http_status(:success)
      expect(json["entries"].map { |e| e["action"] }).to eq(["page.published"])
      expect(json["known_actions"]).to include("page.deleted")
    end

    it "needs audit_log:read" do
      get "/api/audit_log", headers: auth(["pages:read"])
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---- Deploy ------------------------------------------------------------

  describe "deploy" do
    it "reports whether a hook is configured without handing back the URL" do
      Setting.set(Deploys::SETTING_KEY, "url" => "https://hooks.example.com/secret-path")

      get "/api/deploy", headers: auth(["settings:read"])

      expect(response).to have_http_status(:success)
      expect(json["deploy"]["url_set"]).to be(true)
      expect(json["deploy"]["url_host"]).to eq("hooks.example.com")
      expect(response.body).not_to include("secret-path")
    end

    it "refuses to trigger when no hook is set" do
      post "/api/deploy/trigger", headers: auth(["settings:write"])
      expect(response).to have_http_status(:precondition_failed)
    end

    it "refuses to trigger while paused" do
      Setting.set(Deploys::SETTING_KEY, "url" => "https://hooks.example.com/x", "paused" => true)

      post "/api/deploy/trigger", headers: auth(["settings:write"])
      expect(response).to have_http_status(:conflict)
    end

    it "enqueues a build when configured" do
      Setting.set(Deploys::SETTING_KEY, "url" => "https://hooks.example.com/x", "paused" => false)

      expect {
        post "/api/deploy/trigger", headers: auth(["settings:write"])
      }.to have_enqueued_job(Deploys::TriggerJob)

      expect(response).to have_http_status(:accepted)
    end
  end

  # ---- Sitemap -----------------------------------------------------------

  describe "sitemap" do
    it "patches only the sitemap fields, leaving the rest of the SEO blob alone" do
      page = make_page(status: "published", seo: {"meta_title" => "Keep me"})

      patch "/api/sitemap/page/#{page.id}",
        params: {entry: {sitemap_priority: "0.9", noindex: "true"}},
        headers: auth, as: :json

      expect(response).to have_http_status(:success)
      seo = page.reload.seo
      expect(seo["sitemap_priority"]).to eq(0.9)
      expect(seo["noindex"]).to be(true)
      expect(seo["meta_title"]).to eq("Keep me")
    end

    it "clears a value when sent blank, so callers can fall back to the default" do
      page = make_page(status: "published", seo: {"sitemap_priority" => 0.9})

      patch "/api/sitemap/page/#{page.id}",
        params: {entry: {sitemap_priority: ""}}, headers: auth, as: :json

      expect(page.reload.seo).not_to have_key("sitemap_priority")
    end

    it "needs pages:write" do
      page = make_page

      patch "/api/sitemap/page/#{page.id}",
        params: {entry: {noindex: "true"}}, headers: auth(["pages:read"]), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---- Block type seeding ------------------------------------------------

  describe "block type seeding" do
    it "installs the starter pack on an empty site" do
      BlockType.delete_all

      post "/api/block_types/seed", headers: auth(["block_types:write"])

      expect(response).to have_http_status(:created)
      expect(json["seeded"]).to eq(BlockType::Defaults::ALL.size)
      expect(BlockType.count).to eq(BlockType::Defaults::ALL.size)
    end

    it "refuses rather than overwriting hand-edited block types" do
      BlockType.create!(slug: "custom", label: "Custom", fields: [])

      post "/api/block_types/seed", headers: auth(["block_types:write"])

      expect(response).to have_http_status(:conflict)
      expect(BlockType.count).to eq(1)
    end
  end

  # ---- Manifest ----------------------------------------------------------

  describe "manifest" do
    # The brand brief is the surviving half of the removed AI settings screen:
    # it exists to be published here so an external agent writes in the
    # workspace's voice.
    it "publishes the brand brief, omitting fields left blank" do
      Setting.set("brand", "brand_voice" => "Direct and plain.", "audience" => "", "key_facts" => "EU only.")

      get "/api/manifest", headers: auth

      expect(response).to have_http_status(:success)
      expect(json["brand"]).to eq("brand_voice" => "Direct and plain.", "key_facts" => "EU only.")
    end

    it "returns an empty brand rather than nulls when nothing is configured" do
      get "/api/manifest", headers: auth
      expect(json["brand"]).to eq({})
    end
  end
end

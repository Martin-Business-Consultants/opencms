# frozen_string_literal: true

require "rails_helper"

# A form's emails as content: built from FormEmail::BlockTypes in the content
# editor, drawn by the CMS until the Astro site's build sends a template of
# the same blocks, and sent in that template once it matches.
RSpec.describe "Form emails", type: :request do
  let(:admin) { create(:user) }
  let(:form) do
    Form.create!(slug: "contact", title: "Contact", status: "published",
      fields: [{"name" => "name", "label" => "Your name", "type" => "text"},
               {"name" => "email", "label" => "Email", "type" => "email", "required" => true}])
  end
  let(:email) { form.notification_email }

  def api_headers(user) = {"Authorization" => "Bearer #{user.api_token.token}"}

  def deliver(submission)
    FormSubmissionMailer.with(form_email: email.reload, submission: submission, recipients: ["ops@x.test"]).deliver.deliver_now
  end

  describe "the editor" do
    before { sign_in_as admin }

    it "saves an email unchanged when nothing was edited" do
      before = email.blocks

      get edit_form_email_path(form_slug: form.slug, kind: "notification")
      expect(response.body).to include("Submission answers", new_form_email_block_path)
      submit_form_pairs(:patch, form_email_path(form_slug: form.slug, kind: "notification"), form_pairs(response.body, "form_email_form"))

      expect(response).to redirect_to(edit_form_email_path(form_slug: form.slug, kind: "notification"))
      expect(email.reload.blocks).to eq(before)
    end

    it "adds an email block with its defaults" do
      get new_form_email_block_path, params: {type: "email_button", scope: "form_email[blocks]", depth: 1}

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Button", "Visit our site")
      get new_form_email_block_path, params: {type: "hero", scope: "form_email[blocks]"}
      expect(response).to have_http_status(:not_found)
    end

    it "refuses a block missing what it needs" do
      patch form_email_path(form_slug: form.slug, kind: "notification"), params: {form_email: {blocks: {
        "_list" => "1", "r1" => {"type" => "email_heading", "version" => "1", "data" => {"text" => ""}}
      }}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("text is required")
    end

    it "previews the unsaved email for a made-up submission" do
      patch form_email_preview_path(form_slug: form.slug, email_kind: "notification"), params: {form_email: {blocks: {
        "_list" => "1", "r1" => {"type" => "email_heading", "version" => "1", "data" => {"text" => "Hi {{name}}", "level" => "h1", "align" => "left"}}
      }}}

      expect(response.body).to include("Hi Sam Sample")
      expect(email.reload.blocks.first.dig("data", "text")).to eq("New submission to {{form_title}}")
    end

    it "sends a test of the saved email to whoever asks" do
      expect { post form_email_test_path(form_slug: form.slug, email_kind: "notification") }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq([admin.email])
    end
  end

  describe "the CMS's layout" do
    it "draws the blocks with their tokens filled and escaped, the answers as a table" do
      email.update!(blocks: [
        FormEmail::BlockTypes.build("email_text").merge("data" => {"body" => "<p>From {{name}}</p><script>x()</script>"}),
        FormEmail::BlockTypes.build("email_submission")
      ])
      submission = form.submissions.create!(data: {"name" => "<b>Al</b>", "email" => "al@b.test"}, meta: {}, ip: "1.2.3.4")

      html = deliver(submission).body.decoded

      expect(html).to include("From &lt;b&gt;Al&lt;/b&gt;", "Your name", "al@b.test")
      expect(html).not_to include("<script>")
    end

    it "reads an email saved before blocks as its Markdown body" do
      email.update_columns(blocks: [], body: "Hello **{{name}}**")
      submission = form.submissions.create!(data: {"name" => "Al", "email" => "al@b.test"}, meta: {}, ip: "1.2.3.4")

      expect(email.reload.content_blocks.map { it["type"] }).to eq(%w[email_text email_submission])
      expect(deliver(submission).body.decoded).to include("Hello <strong>Al</strong>")
    end
  end

  describe "the site's template" do
    let(:site) { create(:user, admin: false, role: create(:role, permissions: %w[forms:read forms:templates])) }
    let(:template) do
      <<~HTML
        <!doctype html><html><body><h1 class="brand">Hi {{name}}</h1>
        <table><tr data-cms-repeat="answers"><th>{{answer.label}}</th><td>{{answer.value}}</td></tr></table></body></html>
      HTML
    end

    it "lists each email's blocks and digest for the site to build from" do
      get api_form_emails_path(form_slug: form.slug), headers: api_headers(site)

      notification = response.parsed_body["emails"].find { it["kind"] == "notification" }
      expect(notification["blocks"].map { it["type"] }).to eq(%w[email_heading email_text email_submission])
      expect(notification["content_digest"]).to eq(email.content_digest)
    end

    it "sends the site's design once its build sends a template of the current blocks" do
      put api_form_email_template_path(form_slug: form.slug, email_kind: "notification"),
        params: {html: template, digest: email.content_digest}, headers: api_headers(site)
      expect(response.parsed_body["status"]).to eq("current")

      submission = form.submissions.create!(data: {"name" => "<Al>", "email" => "al@b.test"}, meta: {}, ip: "1.2.3.4")
      html = deliver(submission).body.decoded

      expect(html).to include('class="brand"', "Hi &lt;Al&gt;", "<th>Email</th><td>al@b.test</td>", "<th>Your name</th>")
      expect(html).not_to include("data-cms-repeat", "{{")
    end

    it "keeps the CMS's layout while the template is from older blocks" do
      put api_form_email_template_path(form_slug: form.slug, email_kind: "notification"),
        params: {html: template, digest: "older"}, headers: api_headers(site)
      expect(response.parsed_body["status"]).to eq("stale")

      submission = form.submissions.create!(data: {"name" => "Al", "email" => "al@b.test"}, meta: {}, ip: "1.2.3.4")
      expect(deliver(submission).body.decoded).not_to include('class="brand"')
    end

    it "takes a template only from a token allowed to send one" do
      reader = create(:user, admin: false, role: create(:role, permissions: %w[forms:read]))

      put api_form_email_template_path(form_slug: form.slug, email_kind: "notification"),
        params: {html: template, digest: email.content_digest}, headers: api_headers(reader)

      expect(response).to have_http_status(:forbidden)
      expect(email.reload.site_template).to be_nil
    end
  end
end

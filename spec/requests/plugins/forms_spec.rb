# frozen_string_literal: true

require "rails_helper"

# The Forms plugin (engines/forms): the admin screens, and what disappears
# when it's switched off. The API is covered by spec/requests/api/*.
RSpec.describe "The Forms plugin", type: :request do
  let(:admin) { create(:user) }

  def api_headers(user = admin) = {"Authorization" => "Bearer #{user.api_token.token}"}

  def make_form(slug = "contact", **attrs)
    Form.create!({slug: slug, title: slug.titleize, status: "published",
                  fields: [{"name" => "email", "label" => "Email", "type" => "email", "required" => true}]}.merge(attrs))
  end

  describe "the admin" do
    before { sign_in_as admin }

    it "lists forms with their counts, in the Hotwire layout" do
      form = make_form
      form.submissions.create!(data: {"email" => "a@b.test"})

      get forms_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Contact", "contact", "Import JSON", "New form", "Duplicate", form_activation_path(form.slug))
    end

    it "switches a form active and inactive from the list" do
      form = make_form(status: "draft")

      patch form_activation_path(form.slug), params: {active: "1"}
      expect(form.reload.status).to eq("published")

      patch form_activation_path(form.slug), params: {active: "0"}
      expect(form.reload.status).to eq("draft")
    end

    it "duplicates a form as a draft under a free slug, with its emails" do
      form = make_form
      form.notification_email.update!(enabled: true, subject: "New one", recipients: "team@b.test")

      post form_duplication_path(form.slug)
      post form_duplication_path(form.slug)

      copy = Form.find_by!(slug: "contact-copy")
      expect(response).to redirect_to(edit_form_path("contact-copy-2"))
      expect(copy).to have_attributes(title: "Contact (copy)", status: "draft", fields: form.fields)
      expect(copy.notification_email).to have_attributes(enabled: true, subject: "New one", recipients: "team@b.test")
    end

    it "draws the builder: a card per field on the canvas, their settings in the panel" do
      form = make_form

      get edit_form_path(form.slug)

      doc = Nokogiri::HTML(response.body)
      expect(doc.css(".form-canvas > .form-card").size).to eq 1
      expect(doc.css(".form-panel .form-settings[data-key='f0']")).to be_present
      expect(doc.css(".form-palette__item").map { it["data-type"] }).to match_array(FormValidator::FIELD_TYPES)
    end

    it "creates a form from a template, filling in what was left blank" do
      post forms_path, params: {template: "newsletter", form: {title: "", slug: "", status: "draft"}}

      form = Form.find_by!(slug: "newsletter")
      expect(response).to redirect_to(edit_form_path("newsletter"))
      expect(form.fields).to eq(Form::TEMPLATES.find { it[:key] == "newsletter" }[:fields])
      expect(form).to have_attributes(submit_label: "Sign me up", success_message: start_with("You're in."))
      expect(AuditLog.last.action).to eq("form.created")
    end

    it "opens the New form sheet over the list" do
      make_form

      get new_form_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Contact", "dialog--sheet", 'data-dialog-auto-open-value="true"')
    end

    it "reopens the New form sheet with its errors" do
      post forms_path, params: {form: {title: "", slug: "Bad Slug"}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That didn’t work", "dialog--sheet", 'data-dialog-auto-open-value="true"')
    end

    it "won't take a slug the admin's own routes use" do
      post forms_path, params: {form: {title: "Export", slug: "export"}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(Form.find_by(slug: "export")).to be_nil
    end

    it "round-trips every template's fields through the builder unchanged" do
      Form::TEMPLATES.each do |template|
        form = Form.create!(slug: "rt-#{template[:key].tr("_", "-")}", title: template[:name], status: "draft", fields: template[:fields])

        get edit_form_path(form.slug)
        pairs = form_pairs(response.body, "form_editor")
        submit_form_pairs(:patch, form_path(form.slug), pairs)

        expect(response).to redirect_to(edit_form_path(form.slug)), "#{template[:key]}: #{response.body[/That didn’t work.{0,400}/m]}"
        expect(form.reload.fields).to eq(template[:fields]), "#{template[:key]} changed on a save"
      end
    end

    it "saves fields edited in the builder, keeping only what each type uses" do
      form = make_form

      patch form_path(form.slug), params: {form: {title: "Contact us", fields: {
        "a1" => {name: "topic", label: "Topic", type: "select", options: "sales | Sales\nSupport", placeholder: "dropped"},
        "b2" => {name: "cv", label: "CV", type: "file", accept: ".pdf", max_size: "5 MB", multiple: "1", required: "1"},
        "c3" => {name: "note", label: "Note", type: "textarea", placeholder: "Anything else?", extra: '{"width":"half"}'}
      }}}

      expect(form.reload.title).to eq("Contact us")
      expect(form.fields).to eq([
        {"name" => "topic", "label" => "Topic", "type" => "select",
         "options" => [{"value" => "sales", "label" => "Sales"}, {"value" => "Support", "label" => "Support"}]},
        {"name" => "cv", "label" => "CV", "type" => "file", "required" => true, "accept" => ".pdf", "multiple" => true, "max_size" => 5 * 1024 * 1024},
        {"name" => "note", "label" => "Note", "type" => "textarea", "placeholder" => "Anything else?", "width" => "half"}
      ])
    end

    it "saves the webhook sheet's URL and key mapping, dropping rows without a key" do
      form = make_form

      patch form_path(form.slug), params: {form: {fields: {"f0" => {name: "email", label: "Email", type: "email"}},
        notify_webhook_url: "https://hooks.test/in", webhook_body: {mode: "fields", mappings: {
        "m1" => {key: "email_address", source: "field:email", value: "ignored"},
        "m2" => {key: "", source: "meta:ip"},
        "m3" => {key: "lead_source", source: "custom", value: "Website"}
      }}}}

      expect(response).to redirect_to(edit_form_path(form.slug))
      expect(form.reload.notify_webhook_url).to eq("https://hooks.test/in")
      expect(form.webhook_body).to eq("mode" => "fields", "mappings" => [
        {"key" => "email_address", "source" => "field:email"},
        {"key" => "lead_source", "source" => "custom", "value" => "Website"}
      ])

      get edit_form_path(form.slug)
      expect(response.body).to include("dialog--sheet-half", "2 mapped keys", 'value="field:email" selected="selected"')
    end

    it "re-renders the edit page when the fields don't validate" do
      form = make_form

      patch form_path(form.slug), params: {form: {fields: {"a1" => {name: "topic", label: "Topic", type: "select", options: ""}}}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(form.reload.fields.first["name"]).to eq("email")
    end

    it "shows a form's submissions, and one of them with its data" do
      form = make_form
      submission = form.submissions.create!(data: {"email" => "reader@b.test"}, ip: "10.0.0.1")

      get form_path(form.slug)
      expect(response.body).to include("reader@b.test")

      get form_submission_path(form.slug, submission)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Email", "reader@b.test", "10.0.0.1")

      delete form_submission_path(form.slug, submission)
      expect(response).to redirect_to(form_path(form.slug))
      expect(FormSubmission.exists?(submission.id)).to be(false)
    end

    it "edits a form's emails, re-rendering when they don't validate" do
      form = make_form

      get edit_form_email_path(form_slug: form.slug, kind: "notification")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("{{email}}")

      patch form_email_path(form_slug: form.slug, kind: "notification"), params: {form_email: {enabled: "1", subject: "", body: ""}}
      expect(response).to have_http_status(:unprocessable_content)

      patch form_email_path(form_slug: form.slug, kind: "notification"),
        params: {form_email: {enabled: "1", subject: "New", body: "Hi", recipients: "ops@x.test"}}
      expect(form.notification_email.reload).to have_attributes(enabled: true, recipients: "ops@x.test")
    end

    it "moves ticked forms to the trash" do
      make_form("a")
      make_form("b")

      post forms_bulk_deletions_path, params: {slugs: %w[a b]}

      expect(flash[:notice]).to eq("2 forms moved to trash")
      expect(Form.count).to eq(0)
      expect(Form.with_discarded.count).to eq(2)
    end

    it "exports what import reads back" do
      make_form(title: "Round trip")

      get forms_export_path
      json = response.body
      Form.with_discarded.find_each(&:destroy_permanently!)

      post forms_import_path, params: {file: Rack::Test::UploadedFile.new(StringIO.new(json), "application/json", original_filename: "forms.json")}

      expect(flash[:notice]).to eq("Import: 1 created, 0 updated.")
      expect(Form.find_by(slug: "contact").title).to eq("Round trip")
    end

    it "keeps the sender and spam settings in Settings › Forms" do
      get settings_forms_path
      expect(response).to have_http_status(:ok)

      patch settings_forms_path, params: {settings: {from_name: "Old Mill", captcha_provider: "turnstile", turnstile_secret_key: "sekret"}}

      expect(Setting.get("forms_settings")).to include("from_name" => "Old Mill", "captcha_provider" => "turnstile")
      expect(TurnstileVerifier.from_settings).not_to be_nil
    end

    it "keeps captcha secrets encrypted, never shows them, and keeps them when the field is left blank" do
      Setting.set("forms_settings", {"turnstile_secret_key" => "old-plain"})

      patch settings_forms_path, params: {settings: {captcha_provider: "turnstile", turnstile_secret_key: "zq-s3cr3t-77", recaptcha_secret_key: ""}}

      expect(Setting.secret("forms_settings", "turnstile_secret_key")).to eq("zq-s3cr3t-77")
      expect(Setting.get("forms_settings")).not_to have_key("turnstile_secret_key")
      expect(Setting.find_by(key: "forms_settings").read_attribute_before_type_cast(:secrets)).not_to include("zq-s3cr3t-77")

      patch settings_forms_path, params: {settings: {from_name: "Mill", turnstile_secret_key: ""}}
      expect(Forms.captcha_secret("turnstile_secret_key")).to eq("zq-s3cr3t-77")

      get settings_forms_path
      expect(response.body).not_to include("zq-s3cr3t-77")
      expect(response.body).to include("Saved — leave blank to keep")
    end

    it "still reads a secret an older install saved in plain" do
      Setting.set("forms_settings", {"captcha_provider" => "turnstile", "turnstile_secret_key" => "plain"})

      expect(Forms.captcha_secret("turnstile_secret_key")).to eq("plain")
      expect(TurnstileVerifier.from_settings).not_to be_nil
    end

    it "moves plain secrets into the encrypted ones when migrated" do
      require Rails.root.join("engines/forms/db/migrate/20260928090000_encrypt_form_captcha_secrets")
      Setting.set("forms_settings", {"from_name" => "Mill", "turnstile_secret_key" => "plain", "recaptcha_secret_key" => ""})

      EncryptFormCaptchaSecrets.new.up

      expect(Setting.get("forms_settings")).to eq("from_name" => "Mill", "recaptcha_secret_key" => "")
      expect(Setting.secret("forms_settings", "turnstile_secret_key")).to eq("plain")
    end

    it "owns submission.created: a webhook narrows it to chosen forms" do
      webhook = Webhook.create!(name: "a", url: "https://x.test/h", events: %w[submission.created],
        event_filters: Webhook.permitted_event_filters(ActionController::Parameters.new("submission.created" => {"form_slugs" => ["contact", ""]})))

      expect(webhook.event_filters).to eq("submission.created" => {"form_slugs" => ["contact"]})
      expect(webhook.matches_filter?("submission.created", {"form_slug" => "contact"})).to be(true)
      expect(webhook.matches_filter?("submission.created", {"form_slug" => "other"})).to be(false)
      expect(Webhook::EVENTS).not_to include("submission.created")
      expect(Webhook.deploy_events).not_to include("submission.created")

      switch_plugin :forms, on: false
      expect(Webhook.events).to include("submission.created")
      expect(webhook.reload).to be_valid
    end
  end

  describe "switched off" do
    before do
      make_form
      switch_plugin :forms, on: false
    end

    it "takes away its pages, its API and the public endpoint" do
      sign_in_as admin

      get forms_path
      expect(response).to have_http_status(:not_found)
      get submissions_path
      expect(response).to have_http_status(:not_found)
      get settings_forms_path
      expect(response).to have_http_status(:not_found)

      get "/api/forms", headers: api_headers
      expect(response).to have_http_status(:not_found)
      post "/api/forms/contact/submissions", params: {email: "a@b.test"}
      expect(response).to have_http_status(:not_found)
      expect(FormSubmission.count).to eq(0)
    end

    it "leaves the core without it: no menu link, no manifest section, no trash kind, no schedule" do
      sign_in_as admin
      get pages_path
      expect(response.body).not_to include(">Forms<", ">Submissions<")

      get "/api/manifest", headers: api_headers
      manifest = JSON.parse(response.body)
      expect(manifest).not_to have_key("forms")
      expect(manifest["counts"]).not_to have_key("forms")

      expect(Trash.kinds).not_to have_key("form")
      expect(RecurringTasks::Catalog.known?("submission_digest")).to be(false)
      expect(Permissions.catalog).not_to have_key("Forms")
    end

    it "lets a digest schedule wait rather than fail" do
      switch_plugin :forms, on: true
      task = RecurringTask.create!(recipe_key: "submission_digest", cron: "0 9 * * *")
      switch_plugin :forms, on: false

      RecurringTask::RunJob.perform_now(task.id)

      expect(task.reload.last_status).to be_nil
    end
  end
end

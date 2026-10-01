# frozen_string_literal: true

module Forms
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    # The public and API paths are the ones the sites and the CLI already use.
    initializer "forms.routes" do |app|
      app.routes.append do
        # One new block row for a form email's editor (FormEmail::BlockTypes).
        get "form_email_blocks/new", to: "form_email_blocks#new", as: :new_form_email_block

        # Before `resources :forms`, so /forms/export isn't read as a form.
        namespace :forms do
          resource :export, only: :show
          resource :import, only: :create
          resources :bulk_deletions, only: :create
        end

        resources :forms, param: :slug do
          resource :activation, only: :update, controller: "forms/activations"
          resource :duplication, only: :create, controller: "forms/duplications"
          resources :submissions, controller: "form_submissions", only: [:index, :show, :destroy]
          resources :emails, controller: "form_emails", only: [:edit, :update], param: :kind,
            constraints: {kind: /notification|confirmation/} do
            resource :preview, only: [:create, :update], controller: "form_emails/previews", constraints: {email_kind: /notification|confirmation/}
            resource :test, only: :create, controller: "form_emails/tests", constraints: {email_kind: /notification|confirmation/}
          end
        end

        namespace :submissions do
          resources :bulk_deletions, only: :create
        end
        resources :submissions, only: [:index]

        namespace :settings do
          resource :forms, only: [:show, :update], controller: "forms"
        end

        namespace :api, defaults: {format: :json} do
          resources :forms, param: :slug, only: [:index, :show, :create, :update, :destroy] do
            # The form's notification / confirmation email templates.
            resources :emails, controller: "form_emails", only: [:index, :show, :update],
              param: :kind, constraints: {kind: /notification|confirmation/} do
              # Where the Astro site's build sends the template it made (FormEmail::SiteTemplate).
              resource :template, only: :update, controller: "form_email_templates",
                constraints: {email_kind: /notification|confirmation/}
            end
          end

          # Public write path (unauthenticated, CORS) vs. authenticated inbox —
          # different controllers on purpose, see Api::SubmissionsController.
          post    "forms/:form_slug/submissions", to: "form_submissions#create"
          options "forms/:form_slug/submissions", to: "form_submissions#options"
          get     "forms/:form_slug/submissions", to: "submissions#index"

          post "submissions/bulk_destroy", to: "submissions/bulk_deletions#create", as: :bulk_destroy_submissions
          resources :submissions, only: [:index, :show, :destroy]
        end
      end
    end

    # The plugin's own Stimulus controllers (the form builder), pinned
    # beside the admin's (config/importmap.rb).
    initializer "forms.importmap", before: "importmap" do |app|
      app.config.importmap.paths << root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << root.join("app/javascript")
    end

    initializer "forms.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
    end

    initializer "forms.migrations" do |app|
      config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
    end

    config.to_prepare do
      Cms::Plugins.register :forms, name: "Forms", version: "1.0.0", author: "Martin Business Consultants",
        bundled: true, enabled_by_default: true, requires: ">= 1.0",
        description: "Contact, booking and signup forms for the site: their fields and emails, the endpoint " \
                     "the site posts to, spam protection, and the Submissions inbox.",
        adopt_if: -> { Form.with_discarded.exists? || FormSubmission.exists? }

      Cms::Plugins.menu :forms, :forms, label: "Forms", icon: "form", group: "Content", after: :globals,
        path: -> { forms_path }, capability: "forms:read"
      Cms::Plugins.submenu :forms, :forms, label: "All forms", path: -> { forms_path }, capability: "forms:read"
      Cms::Plugins.submenu :forms, :forms, label: "Add new", path: -> { new_form_path }, capability: "forms:write",
        after: "All forms"
      Cms::Plugins.submenu :forms, :forms, label: "Submissions", path: -> { submissions_path },
        capability: "submissions:read", after: "Add new"
      Cms::Plugins.new_item :forms, label: "Form", path: -> { new_form_path }, capability: "forms:write", after: "Global"
      Cms::Plugins.settings :forms, "Forms", -> { settings_forms_path },
        description: "Who form emails come from, and spam protection.", capability: "forms:read",
        group: "Workspace", after: ["Commerce", "Brand context"]
      # forms:templates: the Astro site's build sending the email templates it
      # made (Api::FormEmailTemplatesController), so the site's token has it.
      Cms::Plugins.permissions :forms, "Forms", %w[forms:read forms:write forms:delete forms:templates submissions:read submissions:delete],
        after: "Globals",
        defaults: {editor: %w[forms:read submissions:read], author: %w[forms:read submissions:read],
                   agent: %w[forms:read submissions:read], site: %w[forms:read forms:templates]}
      Cms::Plugins.stylesheet :forms, "forms/forms"

      Cms::Plugins.counts :forms, after: :globals, forms: -> { Form.count }, submissions: -> { FormSubmission.count }
      Cms::Plugins.manifest_section :forms, :forms, -> { Form.ordered.map(&:manifest_entry) }, after: :collections
      Cms::Plugins.trashable :forms, "form", "Form", label: "Forms", after: "entry",
        meta: ->(form) { {status: form.status, slug: form.slug} }
      Cms::Plugins.recurring_recipe :forms, "RecurringTasks::Recipes::SubmissionDigest", after: "content_freshness_report"
      Cms::Plugins.provide :forms, :published_forms, -> { Form.where(status: "published").order(:title).to_a }
      # For Site Health: which spam protection the forms use, and whether it has both its keys.
      Cms::Plugins.provide :forms, :spam_protection, -> {
        provider = Setting.get(Forms::SETTING_KEY)["captcha_provider"].presence_in(%w[turnstile recaptcha])
        site_key = provider && Setting.get(Forms::SETTING_KEY)["#{provider}_site_key"].presence
        {provider: provider, configured: provider.present? && site_key.present? && Forms.captcha_secret("#{provider}_secret_key").present?}
      }
      Cms::Plugins.slot :webhook_filters, :forms, "forms/slots/webhook_filters"
      # A submission doesn't change the public site, so it schedules no rebuild.
      Cms::Plugins.webhook_events :forms, "Forms", %w[submission.created], after: "global.updated"
      Cms::Plugins.webhook_event_filter :forms, FormWebhookFilter::EVENT,
        permit: FormWebhookFilter.method(:permit), validate: FormWebhookFilter.method(:validate),
        match: FormWebhookFilter.method(:match)

      Cms::Plugins.api :forms, "/api/forms", description: "Every form, with its fields; create and update them."
      Cms::Plugins.api :forms, "/api/forms/:slug/submissions", description: "Where the site posts a submission (public, CORS)."
      Cms::Plugins.api :forms, "/api/forms/:slug/emails/:kind/template",
        description: "Where the site's build sends the email template it made from an email's blocks."
      Cms::Plugins.api :forms, "/api/submissions", description: "The submissions inbox, across every form."
    end
  end
end

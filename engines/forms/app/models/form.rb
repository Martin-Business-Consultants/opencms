# frozen_string_literal: true

# A reusable form definition. Fields are described as a JSON array; the
# Astro renderer turns them into HTML inputs. Submissions are not stored
# server-side yet — submit_url points at wherever the form should POST
# (mailto:, Formspree, custom endpoint, etc.).
class Form < ApplicationRecord
  include ListSearchable

  search_on :title, :slug

  include SoftDeletable
  include Eventable

  has_many :submissions, class_name: "FormSubmission", dependent: :destroy
  has_many :emails, class_name: "FormEmail", dependent: :destroy

  after_create :seed_default_emails

  def notification_email = emails.find_by(kind: "notification")

  def confirmation_email = emails.find_by(kind: "confirmation")

  STATUSES    = %w[draft published archived].freeze
  SLUG_FORMAT = /\A[a-z0-9][a-z0-9\-]*\z/

  # Allowed field types. Keep this small until a real use case forces growth.
  FIELD_TYPES = FormValidator::FIELD_TYPES

  # Field types that require an `options` array.
  OPTIONED_TYPES = FormValidator::OPTIONED_TYPES

  # Submission honeypot: a hidden field bots fill in. If non-empty, drop the
  # submission silently. Keep both renderer and submissions controller in sync
  # with this name.
  HONEYPOT_FIELD = FormValidator::HONEYPOT_FIELD

  # Default per-file size cap for file-typed fields, overridable per-field.
  DEFAULT_MAX_FILE_BYTES = FormValidator::DEFAULT_MAX_FILE_BYTES

  # Starter templates surfaced from the "New form" dialog. Each template
  # provides a default slug + title + field set; the user can override slug
  # and title before creating. Order here = order in the picker.
  TEMPLATES = [
    {
      key: "contact",
      name: "Contact",
      description: "General-purpose contact form with name, email, topic, message.",
      defaults: {slug: "contact", title: "Get in Touch", submit_label: "Send message"},
      fields: [
        {"name" => "name",  "label" => "Your name", "type" => "text",  "required" => true},
        {"name" => "email", "label" => "Email",     "type" => "email", "required" => true},
        {"name" => "topic", "label" => "Topic", "type" => "select", "required" => true,
         "options" => [
           {"value" => "general",  "label" => "General inquiry"},
           {"value" => "feedback", "label" => "Feedback"},
           {"value" => "press",    "label" => "Press"}
         ]},
        {"name" => "message", "label" => "Message", "type" => "textarea", "required" => true}
      ]
    },
    {
      key: "catering",
      name: "Catering inquiry",
      description: "Date, headcount, location, dietary needs.",
      defaults: {slug: "catering", title: "Catering Inquiry", submit_label: "Send inquiry"},
      fields: [
        {"name" => "name",        "label" => "Your name", "type" => "text",  "required" => true},
        {"name" => "email",       "label" => "Email",     "type" => "email", "required" => true},
        {"name" => "phone",       "label" => "Phone",     "type" => "tel"},
        {"name" => "event_date",  "label" => "Event date (approximate)", "type" => "text", "required" => true,
         "placeholder" => "e.g. Saturday, June 14"},
        {"name" => "headcount",   "label" => "Headcount", "type" => "text", "required" => true},
        {"name" => "location",    "label" => "Location",  "type" => "text"},
        {"name" => "dietary",     "label" => "Dietary restrictions", "type" => "textarea"},
        {"name" => "message",     "label" => "Anything else?", "type" => "textarea"}
      ]
    },
    {
      key: "private_event",
      name: "Private event booking",
      description: "Reserve a section or the whole space.",
      defaults: {slug: "private-event", title: "Book a Private Event", submit_label: "Request booking"},
      fields: [
        {"name" => "name",       "label" => "Your name", "type" => "text",  "required" => true},
        {"name" => "email",      "label" => "Email",     "type" => "email", "required" => true},
        {"name" => "phone",      "label" => "Phone",     "type" => "tel"},
        {"name" => "event_type", "label" => "Type of event", "type" => "select", "required" => true,
         "options" => [
           {"value" => "birthday",   "label" => "Birthday"},
           {"value" => "corporate",  "label" => "Corporate / team dinner"},
           {"value" => "rehearsal",  "label" => "Rehearsal dinner"},
           {"value" => "celebration", "label" => "Celebration"},
           {"value" => "other",      "label" => "Other"}
         ]},
        {"name" => "date",        "label" => "Date", "type" => "text", "required" => true,
         "placeholder" => "e.g. Friday, July 19"},
        {"name" => "headcount",   "label" => "Estimated headcount", "type" => "text", "required" => true},
        {"name" => "budget",      "label" => "Budget", "type" => "text"},
        {"name" => "special_requests", "label" => "Special requests", "type" => "textarea"}
      ]
    },
    {
      key: "careers",
      name: "Job application",
      description: "Apply to work in the kitchen, behind the bar, or front of house.",
      defaults: {slug: "careers", title: "Apply to Work With Us", submit_label: "Submit application"},
      fields: [
        {"name" => "name",  "label" => "Your name", "type" => "text",  "required" => true},
        {"name" => "email", "label" => "Email",     "type" => "email", "required" => true},
        {"name" => "phone", "label" => "Phone",     "type" => "tel"},
        {"name" => "position", "label" => "Position", "type" => "select", "required" => true,
         "options" => [
           {"value" => "kitchen", "label" => "Kitchen / line cook"},
           {"value" => "bar",     "label" => "Bartender / server"},
           {"value" => "host",    "label" => "Host"},
           {"value" => "other",   "label" => "Other"}
         ]},
        {"name" => "availability", "label" => "Availability", "type" => "textarea",
         "help" => "Days and shifts you can work"},
        {"name" => "resume", "label" => "Resume", "type" => "file", "required" => true,
         "accept" => ".pdf,.doc,.docx", "help" => "PDF or Word doc, up to 10 MB."},
        {"name" => "cover_letter", "label" => "Anything else we should know?", "type" => "textarea"}
      ]
    },
    {
      key: "newsletter",
      name: "Newsletter signup",
      description: "Email-only signup with interest tags.",
      defaults: {slug: "newsletter", title: "Get the Newsletter", submit_label: "Sign me up",
                 success_message: "You're in. Watch your inbox for the next dispatch."},
      fields: [
        {"name" => "email", "label" => "Email", "type" => "email", "required" => true},
        {"name" => "name",  "label" => "Name (optional)", "type" => "text"},
        {"name" => "interest", "label" => "Most interested in", "type" => "select",
         "options" => [
           {"value" => "all",     "label" => "Everything"},
           {"value" => "beer",    "label" => "New beer releases"},
           {"value" => "food",    "label" => "Food specials"},
           {"value" => "events",  "label" => "Events & live music"}
         ]}
      ]
    },
    {
      key: "vendor",
      name: "Vendor inquiry",
      description: "For suppliers and service providers reaching out.",
      defaults: {slug: "vendor", title: "Vendor Inquiry", submit_label: "Send inquiry"},
      fields: [
        {"name" => "company",      "label" => "Company name", "type" => "text",  "required" => true},
        {"name" => "contact_name", "label" => "Your name",    "type" => "text",  "required" => true},
        {"name" => "email",        "label" => "Email",        "type" => "email", "required" => true},
        {"name" => "phone",        "label" => "Phone",        "type" => "tel"},
        {"name" => "vendor_type",  "label" => "What do you offer?", "type" => "select", "required" => true,
         "options" => [
           {"value" => "ingredients", "label" => "Ingredients / produce"},
           {"value" => "beverage",    "label" => "Beverage products"},
           {"value" => "equipment",   "label" => "Equipment"},
           {"value" => "service",     "label" => "Service / maintenance"},
           {"value" => "other",       "label" => "Other"}
         ]},
        {"name" => "message", "label" => "Tell us more", "type" => "textarea", "required" => true}
      ]
    },
    {
      key: "press",
      name: "Press inquiry",
      description: "For journalists and media on a deadline.",
      defaults: {slug: "press", title: "Press Inquiry", submit_label: "Send inquiry"},
      fields: [
        {"name" => "outlet",   "label" => "Publication / outlet", "type" => "text",  "required" => true},
        {"name" => "name",     "label" => "Your name",  "type" => "text",  "required" => true},
        {"name" => "email",    "label" => "Email",      "type" => "email", "required" => true},
        {"name" => "deadline", "label" => "Deadline",   "type" => "text",  "placeholder" => "e.g. Friday at 3 PM ET"},
        {"name" => "angle",    "label" => "Story angle", "type" => "textarea", "required" => true},
        {"name" => "message",  "label" => "Anything else?", "type" => "textarea"}
      ]
    },
    {
      key: "reservation",
      name: "Reservation request",
      description: "Walk-ins are usual; this is for asking about exceptions.",
      defaults: {slug: "reservation", title: "Reservation Request", submit_label: "Request reservation"},
      fields: [
        {"name" => "name",       "label" => "Your name", "type" => "text",  "required" => true},
        {"name" => "email",      "label" => "Email",     "type" => "email", "required" => true},
        {"name" => "phone",      "label" => "Phone",     "type" => "tel",   "required" => true},
        {"name" => "party_size", "label" => "Party size", "type" => "text", "required" => true},
        {"name" => "date",       "label" => "Preferred date", "type" => "text", "required" => true},
        {"name" => "time",       "label" => "Preferred time", "type" => "text", "required" => true},
        {"name" => "occasion",   "label" => "Special occasion?", "type" => "text"}
      ]
    },
    {
      key: "release_notify",
      name: "Beer release notify-me",
      description: "Sign up for new release alerts.",
      defaults: {slug: "release-notify", title: "Notify Me About New Beer Releases",
                 submit_label: "Notify me",
                 success_message: "You're on the list. We'll email when the next one drops."},
      fields: [
        {"name" => "email", "label" => "Email", "type" => "email", "required" => true},
        {"name" => "style", "label" => "Most interested in", "type" => "select",
         "options" => [
           {"value" => "all",      "label" => "All releases"},
           {"value" => "ipa",      "label" => "IPAs and pale ales"},
           {"value" => "stout",    "label" => "Stouts and porters"},
           {"value" => "lager",    "label" => "Lagers"},
           {"value" => "specialty", "label" => "Specialty / barrel-aged"}
         ]}
      ]
    },
    {
      key: "feedback",
      name: "Feedback",
      description: "Quick post-visit feedback with rating.",
      defaults: {slug: "feedback", title: "How Was Your Visit?", submit_label: "Send feedback",
                 success_message: "Thanks — we read every one."},
      fields: [
        {"name" => "rating", "label" => "Overall rating", "type" => "radio", "required" => true,
         "options" => [
           {"value" => "5", "label" => "★★★★★ Excellent"},
           {"value" => "4", "label" => "★★★★ Good"},
           {"value" => "3", "label" => "★★★ Okay"},
           {"value" => "2", "label" => "★★ Below expectations"},
           {"value" => "1", "label" => "★ Poor"}
         ]},
        {"name" => "visit_date", "label" => "When did you visit?", "type" => "text"},
        {"name" => "what_was_great", "label" => "What was great?", "type" => "textarea"},
        {"name" => "what_could_improve", "label" => "What could be better?", "type" => "textarea"},
        {"name" => "name",    "label" => "Your name (optional)",  "type" => "text"},
        {"name" => "email",   "label" => "Email (optional)",      "type" => "email",
         "help" => "Only if you'd like a response."},
        {"name" => "contact_ok", "label" => "It's okay to follow up with me about this", "type" => "checkbox"}
      ]
    }
  ].freeze

  validates :slug,         presence: true, uniqueness: true, format: {with: SLUG_FORMAT}
  validates :slug,         exclusion: {in: ->(_) { RESERVED_SLUGS }, message: "is used by the admin"}, on: :create
  validates :title,        presence: true
  validates :status,       inclusion: {in: STATUSES}
  validates :submit_label, presence: true
  validate  :validate_fields_shape_via_validator

  scope :ordered, -> { order(:slug) }

  # A draft copy under a free slug ("contact-copy", "contact-copy-2"…), with
  # the same fields, messages and emails; submissions stay with the original.
  def duplicate!
    base = "#{slug}-copy"
    copy_slug = base
    n = 1
    copy_slug = "#{base}-#{n += 1}" while Form.with_discarded.exists?(slug: copy_slug)

    transaction do
      copy = Form.create!(attributes.slice("fields", "submit_label", "submit_url", "success_message", "notify_webhook_url", "webhook_body")
        .merge("title" => "#{title} (copy)", "slug" => copy_slug, "status" => "draft"))
      emails.each do |email|
        copy.emails.find_by!(kind: email.kind).update!(email.attributes.slice("enabled", "subject", "body", "blocks", "from_field", "recipients"))
      end
      copy
    end
  end

  def file_fields
    fields.select { |f| f.is_a?(Hash) && f["type"] == "file" }
  end

  # Validate an inbound submission's `data` hash and `files` map (field_name
  # => Array<ActionDispatch::Http::UploadedFile>). Returns
  # { "field_name" => [msg, ...] } — empty when valid.
  def validate_submission(data, files = {})
    FormValidator.validate_submission(fields, data, files)
  end

  # The form in /api/manifest's `forms`: what a site needs to render and post it.
  def manifest_entry
    {
      slug:             slug,
      title:            title,
      status:           status,
      submission_url:   "/api/forms/#{slug}/submissions",
      honeypot_field:   HONEYPOT_FIELD,
      submit_label:     submit_label,
      success_message:  success_message,
      submission_count: submissions.count,
      fields:           fields
    }
  end

  # Slugs the admin's own routes use under /forms/, which a form can't take.
  RESERVED_SLUGS = %w[new export import bulk_deletions].freeze

  private

  def validate_fields_shape_via_validator
    FormValidator.validate_fields_shape(fields).each { |msg| errors.add(:fields, msg) }
  end

  # Auto-create the two FormEmail rows whenever a Form is created, both
  # switched off, with blocks to start from: the editor turns them on once
  # the recipients and the words are right.
  def seed_default_emails
    return if emails.exists?

    emails.create!(
      kind:    "notification",
      enabled: false,
      subject: "[#{title}] New submission \#{{submission_id}}",
      blocks:  [
        FormEmail::BlockTypes.build("email_heading").merge("data" => {"text" => "New submission to {{form_title}}", "level" => "h2", "align" => "left"}),
        FormEmail::BlockTypes.build("email_text").merge("data" => {"body" => "<p>Submitted at {{submitted_at}} from {{ip}}.</p>"}),
        FormEmail::BlockTypes.build("email_submission")
      ]
    )
    emails.create!(
      kind:    "confirmation",
      enabled: false,
      subject: "Thanks for your submission",
      blocks:  [
        FormEmail::BlockTypes.build("email_heading").merge("data" => {"text" => "Thanks for reaching out", "level" => "h1", "align" => "left"}),
        FormEmail::BlockTypes.build("email_text").merge("data" => {
          "body" => "<p>We got your message and will get back to you within one business day.</p><p>— The team</p>"
        })
      ]
    )
  end
end

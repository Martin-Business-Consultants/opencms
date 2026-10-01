# frozen_string_literal: true

# Per-collection event email — fires when an entry of a notification-
# subscribed collection moves through one of the configured events. The
# template renders a centered branding logo, the event verb, the entry's
# title/slug/status, and a link back to the editor.
class CollectionEventMailer < ApplicationMailer
  DEFAULT_FROM_NAME  = "Notifications"
  # Outsend only accepts mail from a domain the account owns, so an
  # unconfigured site falls back to the credentialed sender rather
  # than to an address that would bounce at the relay.
  def self.default_from_email = ApplicationMailer.from_address

  EVENT_VERBS = {
    "entry.created"     => "created",
    "entry.updated"     => "updated",
    "entry.published"   => "published",
    "entry.unpublished" => "unpublished",
    "entry.deleted"     => "deleted"
  }.freeze

  def event
    @collection = params[:collection]
    @entry      = params[:entry]
    @event      = params[:event]
    @payload    = (params[:payload] || {}).with_indifferent_access
    recipients  = params[:recipients]

    # The core's sender (Settings › General), then the Forms plugin's, which
    # this mailer used before there was a core one, then the defaults.
    general    = Setting.get("general")
    forms      = Setting.get("forms_settings")
    from_name  = general["email_from_name"].presence || forms["from_name"].presence || DEFAULT_FROM_NAME
    from_email = general["email_from_address"].presence || forms["from_email"].presence || self.class.default_from_email

    @verb     = EVENT_VERBS[@event] || @event
    @logo_url = compute_logo_url
    @entry_url = compute_entry_url

    mail(
      from:    "\"#{from_name}\" <#{from_email}>",
      to:      recipients,
      subject: "[#{@collection.name}] entry #{@verb}: #{entry_title}"
    )
  end

  private

  def entry_title
    (@entry&.title.presence) || @payload["title"].to_s.presence || "(untitled)"
  end

  def compute_logo_url
    branding = Setting.get("branding")
    logo_id  = branding["logo_id"]
    return nil if logo_id.blank?

    asset = Asset.with_attached_file.find_by(id: logo_id)
    return nil unless asset&.file&.attached?

    base = absolute_base_url
    return nil if base.empty?

    path = Rails.application.routes.url_helpers.rails_blob_path(asset.file, only_path: true)
    "#{base}#{path}"
  rescue StandardError
    nil
  end

  def compute_entry_url
    return nil unless @entry

    base = absolute_base_url
    return nil if base.empty?

    "#{base}/collections/#{@collection.slug}/entries/#{@entry.slug}/edit"
  rescue StandardError
    nil
  end

  def absolute_base_url
    Setting.get("general")["site_base_url"].to_s.sub(%r{/+\z}, "")
  end
end

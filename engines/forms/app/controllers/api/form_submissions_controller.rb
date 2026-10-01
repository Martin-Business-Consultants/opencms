# frozen_string_literal: true

# Public, unauthenticated form submission endpoint. Browsers POST here from
# the static Astro site. Protections in order:
#   1. Honeypot field (HONEYPOT_FIELD on Form). Filled => silently 201.
#   2. Rate limit per IP+slug via Rails 7.2+ ActionController::RateLimiting.
#   3. Cloudflare Turnstile, when a Turnstile secret key is configured in the
#      `forms_settings` Setting. The token is read from `cf-turnstile-response`
#      (the widget's default field name) or `turnstile_token`; a missing or
#      rejected token => 422 {error: "captcha_failed"}. See TurnstileVerifier.
#   4. Schema validation against the form definition (required fields,
#      type-specific checks, file size/MIME).
#
# Multipart payloads are handled natively by Rails. File-typed fields arrive
# as ActionDispatch::Http::UploadedFile instances; we attach them to the
# FormSubmission via Active Storage.
class Api::FormSubmissionsController < Api::BaseController
  include PluginGated
  plugin :forms

  # CORS allowlist shared with the quote-request endpoint — see Api::PublicCors.
  include Api::PublicCors

  skip_before_action :authenticate_api, only: [:create, :options]
  before_action :set_cors_headers, only: [:create, :options]

  rate_limit to: 5, within: 10.minutes, only: :create,
    by:   -> { "form_submissions:#{request.ip}:#{params[:form_slug]}" },
    with: -> { render json: {error: "rate_limited"}, status: :too_many_requests }

  def create
    @form = form = Form.where(status: "published").find_by(slug: params[:form_slug])
    unless form
      render json: {error: "not_found"}, status: :not_found
      return
    end

    if params[Form::HONEYPOT_FIELD].present?
      Rails.logger.info("[forms] honeypot tripped for slug=#{form.slug} ip=#{request.ip}")
      render :accepted, status: :created
      return
    end

    unless captcha_passed?
      Rails.logger.info("[forms] captcha failed for slug=#{form.slug} ip=#{request.ip}")
      render json: {error: "captcha_failed"}, status: :unprocessable_entity
      return
    end

    data, files = extract(form)
    errors = form.validate_submission(data, files)
    if errors.any?
      render json: {error: "invalid", errors: errors}, status: :unprocessable_entity
      return
    end

    @submission = submission = form.submissions.create!(
      data: data,
      meta: {
        user_agent: request.user_agent,
        referer:    request.referer
      },
      ip: request.ip
    )

    files.each do |field_name, uploads|
      Array(uploads).each { |u| submission.files.attach(io: u, filename: u.original_filename, content_type: u.content_type, metadata: {field: field_name}) }
    end

    render :create, status: :created
  end

  private

  TURNSTILE_TOKEN_PARAMS = %w[cf-turnstile-response turnstile_token].freeze

  # True when no Turnstile secret is configured — the endpoint then behaves
  # as it always has.
  def captcha_passed?
    verifier = TurnstileVerifier.from_settings
    return true unless verifier

    token = TURNSTILE_TOKEN_PARAMS.lazy.map { |k| params[k].presence }.find(&:itself)
    verifier.verify(token, remote_ip: request.remote_ip)
  end

  # Pull data + files out of params using the form's field schema as the
  # source of truth. Anything not declared on the form is ignored.
  def extract(form)
    data = {}
    files = {}
    form.fields.each do |fd|
      next unless fd.is_a?(Hash)

      name = fd["name"]
      if fd["type"] == "file"
        files[name] = Array(params[name]).reject(&:blank?)
      else
        v = params[name]
        data[name] = v unless v.nil?
      end
    end
    [data, files]
  end
end

# frozen_string_literal: true

require "net/http"

# Records everything a sequence of requests does that someone outside this
# process could see, so a refactor can prove it changed none of it (STYLE.md:
# snapshot /api before and after). Per step it keeps:
#
#   * the response: status, media type, body
#   * the audit rows written
#   * the webhook requests sent (URL, headers, body), by performing the
#     delivery jobs the step enqueued against a stubbed Net::HTTP
#   * every other job enqueued, with its arguments
#   * the "*.cms" notifications published in-process
#   * the mail delivered
#
# Random secrets (tokens, codes) are masked so two runs compare equal. Use it
# from a request spec under frozen time, and write the result somewhere to
# diff:
#
#   recorder = ContractSnapshot::Recorder.new(self)
#   recorder.step("create a page") { post "/api/pages", params: …, headers: … }
#   File.write(path, recorder.to_json)
module ContractSnapshot
  SECRET = /\b(?:mbcs?|whsec|cmsd|cmsu|cmsa|lmn)_[A-Za-z0-9_\-]{8,}/
  TOKEN_FIELDS = %w[token secret code device_code user_code otp_secret totp_secret].freeze
  # Values that differ run to run for reasons nobody downstream relies on (a
  # gzip archive's size varies with its header's timestamp).
  VOLATILE_FIELDS = %w[bytes].freeze

  WEBHOOK_JOBS = %w[DeliverWebhookJob Webhook::DeliveryJob].freeze

  class Recorder
    def initialize(spec)
      @spec = spec
      @steps = []
      @sent = []
      sent = @sent
      spec.allow_any_instance_of(Net::HTTP).to spec.receive(:request) do |http, request|
        sent << {
          "url" => "#{http.use_ssl? ? "https" : "http"}://#{http.address}:#{http.port}#{request.path}",
          "headers" => request.each_header.to_h.except("accept-encoding", "accept", "host"),
          "body" => request.body
        }
        Net::HTTPOK.new("1.1", "200", "OK").tap do |ok|
          ok.instance_variable_set(:@body, "ok")
          ok.instance_variable_set(:@read, true)
        end
      end
    end

    def step(name)
      audit_from = AuditLog.maximum(:id).to_i
      mail_from = ActionMailer::Base.deliveries.size
      queue.clear
      notes = []
      subscriber = ActiveSupport::Notifications.subscribe(/\.cms\z/) do |event_name, _start, _finish, _id, payload|
        notes << [event_name, ContractSnapshot.normalize(payload)]
      end

      error = nil
      begin
        yield
      rescue StandardError => e
        # A step that raises is recorded as such rather than ending the run:
        # the snapshot has to show the same failure after a refactor too.
        error = "#{e.class}: #{e.message.lines.first.to_s.strip}"
      end
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      jobs = queue.map(&:dup)
      queue.clear
      webhook_jobs, other_jobs = jobs.partition { |job| WEBHOOK_JOBS.include?(job[:job].to_s) }

      @steps << {
        "step" => name,
        "error" => error,
        "response" => response_record,
        "audit" => AuditLog.where("id > ?", audit_from).order(:id).map { |row| audit_record(row) },
        "webhooks" => webhook_jobs.map { |job| deliver(job) },
        "jobs" => other_jobs.map { |job| {"job" => job[:job].to_s, "args" => ContractSnapshot.normalize(job[:args])} },
        "notifications" => notes,
        "mail" => ActionMailer::Base.deliveries.drop(mail_from).map { |mail| mail_record(mail) }
      }
    end

    def to_json(*) = JSON.pretty_generate(@steps)

    private

    def queue = ActiveJob::Base.queue_adapter.enqueued_jobs

    def response_record
      return nil unless @spec.respond_to?(:response) && @spec.response

      body = @spec.response.media_type.to_s.include?("json") ? ContractSnapshot.mask(@spec.response.body) : ContractSnapshot.html_digest(@spec.response)
      {"status" => @spec.response.status, "media_type" => @spec.response.media_type, "location" => @spec.response.location, "body" => body}
    rescue StandardError
      nil
    end

    def audit_record(row)
      row.attributes.except("id").transform_values { |value| ContractSnapshot.normalize(value) }
    end

    # A delivery job's arguments are the webhook, the event and its payload.
    # Performing it records the request exactly as a receiver would get it.
    def deliver(job)
      @sent.clear
      job_class = job[:job].is_a?(Class) ? job[:job] : job[:job].to_s.constantize
      job_class.perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
      {"args" => ContractSnapshot.normalize(job[:args]), "sent" => @sent.map(&:dup)}
    end

    def mail_record(mail)
      {"to" => mail.to, "subject" => mail.subject, "body" => ContractSnapshot.mask(mail.body.encoded.to_s.gsub(/\r\n/, "\n")).lines.reject { it.start_with?("Message-ID", "Date:") }.join}
    end
  end

  module_function

  def normalize(value)
    case value
    when ActiveRecord::Base then "#{value.class.name}##{value.id}"
    when Hash
      value.to_h do |k, v|
        masked = if TOKEN_FIELDS.include?(k.to_s) && v.is_a?(String) then "<secret>"
        elsif VOLATILE_FIELDS.include?(k.to_s) then "<varies>"
        else normalize(v)
        end
        [k.to_s, masked]
      end
    when Array then value.map { normalize(it) }
    when Time, DateTime, ActiveSupport::TimeWithZone then value.utc.iso8601(6)
    when String then mask(value)
    when Symbol then value.to_s
    else value
    end
  end

  def mask(text) = text.to_s.gsub(SECRET, "<secret>")

  # HTML pages change with every template tweak; what matters to a refactor of
  # events is that the page still answered the same way.
  def html_digest(response)
    response.redirect? ? nil : "#{response.body.bytesize > 0 ? "html" : "empty"}"
  end
end

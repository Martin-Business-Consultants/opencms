# frozen_string_literal: true

# Something happened, and this is the one place it goes out from. Modelled on
# Fizzy's Event, with two kinds, because this app has always had two
# audiences:
#
#   * Event.record — something a person or a token did ("page.deleted",
#     "service_token.revealed"). Written to the audit log, the event store
#     (who, what, to what, from where; AuditLog), and published in-process as
#     "event.cms". Models call it through Eventable#track_event.
#
#   * Event.announce — a state change the outside world subscribes to, in the
#     webhook vocabulary (Webhook.events: page.published, submission.created
#     …, plus "<kind>.created" for in-process listeners only). Published
#     in-process as "<name>.cms", delivered to every webhook that wants it,
#     handed to the subject's own subscribers (a collection's email
#     notifications) and to the site's deploy hook. Models call it through
#     Eventable#announce — Announceable does so for content transitions.
#
# The two vocabularies differ on purpose: one editorial action can announce
# several transitions (a bulk publish), and an announcement can have no
# person behind it (the scheduler, a visitor's form submission). Both go
# through here, so there is one place that knows who hears about what.
module Event
  module_function

  # `actor` is whoever Current says is acting, unless the event names someone
  # else: the person signing in, before they're Current; the requester of a
  # job's work.
  def record(action, target: nil, actor: Current.actor, **particulars)
    particulars = particulars.merge(via: Current.via) if Current.via

    AuditLog.record(
      action: action,
      target: target,
      actor: actor,
      metadata: particulars,
      ip: Current.remote_ip,
      user_agent: Current.user_agent
    ).tap do
      ActiveSupport::Notifications.instrument("event.cms", action: action, target: target, particulars: particulars)
    end
  end

  def announce(name, payload, subject: nil)
    if Webhook.events.include?(name)
      ActiveSupport::Notifications.instrument("#{name}.cms", event: name, data: payload)
      Webhook.deliver_later(name, payload)
      Deploys.schedule_later(reason: name) if Webhook.deploy_events.include?(name)
    else
      # Not something webhooks carry (<kind>.created), but plugins still hear it.
      ActiveSupport::Notifications.instrument("#{name}.cms", event: name, data: payload, record: subject)
    end

    subject.notify_subscribers(name, payload) if subject.respond_to?(:notify_subscribers)
  end
end

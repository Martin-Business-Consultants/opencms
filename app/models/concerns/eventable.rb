# frozen_string_literal: true

# A model's side of Event.
#
#   page.track_event(:deleted, path: page.path)   # "page.deleted", audited
#   page.announce("page.published")                # webhooks and subscribers
#
# `track_event` records something a person or token did to this record: the
# action is prefixed with the model's name (`eventable_prefix`, which a model
# overrides when its events have always used another, as CollectionEntry's
# "entry." does) and `particulars` become the audit row's metadata. The
# class-level `track_event` is for events about a set of records, such as a
# bulk deletion, which name no single target.
#
# `announce` publishes a state change under its webhook name, with the
# record's `webhook_payload` unless given another.
module Eventable
  extend ActiveSupport::Concern

  class_methods do
    def track_event(action, **particulars)
      Event.record("#{eventable_prefix}.#{action}", **particulars)
    end

    def eventable_prefix
      model_name.singular
    end
  end

  def track_event(action, **particulars)
    Event.record("#{self.class.eventable_prefix}.#{action}", target: self, **particulars)
  end

  def announce(name, payload = webhook_payload)
    Event.announce(name, payload, subject: self)
  end
end

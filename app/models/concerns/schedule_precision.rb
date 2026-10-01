# frozen_string_literal: true

# publish_at and unpublish_at to the second. The schedule inputs show a time
# to the second (in the site's zone), so an untouched field posts back
# "…:20" for a stored "…:20.481"; keeping the stored value when the posted
# one is the same second stops that from reading as a new schedule (which a
# writer's PublicationGate would take back, and every save would re-date).
module SchedulePrecision
  extend ActiveSupport::Concern

  %w[publish_at unpublish_at].each do |name|
    define_method(:"#{name}=") do |value|
      current = public_send(name)
      incoming = value.is_a?(String) ? Time.zone.parse(value) : value
      super((current && incoming && current.to_i == incoming.to_i) ? current : value)
    rescue ArgumentError
      super(value)
    end
  end
end

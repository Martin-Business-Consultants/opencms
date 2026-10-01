# frozen_string_literal: true

# Who filed a finding, as far as the core knows: nobody in particular. A
# plugin that files findings includes its own module after this one to say
# more — the Agents plugin names the agent whose run filed it and links to
# the run.
module Recommendation::Filing
  extend ActiveSupport::Concern

  included do
    # What a list of findings preloads besides the subject: whatever tells
    # who filed each (a plugin's association).
    class_attribute :filer_includes, default: []
    scope :preloaded, -> { includes(:subject, *filer_includes) }
  end

  # The filer's name, and url_for options for reading more; nil for a finding
  # a person or a script filed.
  def filed_by = nil
  def filed_by_link = nil

  # The run a finding came from, when the caller names one; nothing unless a
  # plugin that keeps runs says otherwise.
  def filed_during(_run_id) = nil
end

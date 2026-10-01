# frozen_string_literal: true

# Deciding a revision needs the same capability as publishing the record it
# changes — approving one *is* publishing it — so pages need `pages:publish`,
# entries `entries:publish`, globals `globals:publish`.
module RevisionDecisions
  extend ActiveSupport::Concern

  included do
    helper_method :can_decide_revision?
  end

  private

  def set_revision
    @revision = Revision.find(params[:revision_id])
  end

  def can_decide_revision?(revision)
    Current.user&.can?("#{revision_capability_prefix(revision.revisable_type)}:publish") || false
  end

  def revision_capability_prefix(type)
    case type
    when "Page"   then "pages"
    when "Global" then "globals"
    else "entries"
    end
  end

  def forbidden! = raise(Authorization::Forbidden, "revision.decide")
end

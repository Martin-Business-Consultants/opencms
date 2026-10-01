# frozen_string_literal: true

# Which agent run proposed a revision, as far as the core knows: none. The
# core has no runs; the Agents plugin includes its own module after this one
# (Agents::ProposalFiler) to link the run named by Revision.propose!'s run_id.
module Revision::Proposal
  def proposed_during(_run_id) = nil
end

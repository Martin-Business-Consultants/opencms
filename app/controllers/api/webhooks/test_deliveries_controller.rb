# frozen_string_literal: true

# POST /api/webhooks/:id/test — enqueues a synthetic delivery so the receiving
# end can be verified without waiting for a real content change. 202: the
# delivery happens in a job, so a 200 here would claim more than we know.
class Api::Webhooks::TestDeliveriesController < Api::BaseController
  include Api::WebhookScoped

  requires_capability "webhooks:write", only: [:create]

  def create
    @webhook.deliver_test
    render "api/shared/enqueued", status: :accepted
  end
end

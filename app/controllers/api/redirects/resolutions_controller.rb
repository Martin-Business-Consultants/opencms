# frozen_string_literal: true

# GET /api/redirects/resolve?path=/foo — which rule a request path lands on,
# counted as a hit. Capability-free, like the edge payload.
class Api::Redirects::ResolutionsController < Api::BaseController
  def show
    @match = Redirect.resolve(params[:path])
  end
end

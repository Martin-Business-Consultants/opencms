# frozen_string_literal: true

# Draft previews on the public site. A client mints a token for a page and
# pushes unsaved state here; the Astro site renders it at
# /_preview/<path>?preview=<token> by reading #show. The CMS no longer renders
# pages itself.
class Api::PreviewDraftsController < Api::BaseController
  # Public draft read. The Astro frontend (or any consumer) GETs this to
  # render a draft on the *public* site when `?preview=<token>` is on the
  # URL. The token's TTL is enforced inside `Preview.verify` — expired
  # tokens 404. No bearer auth: the token *is* the auth.
  skip_before_action :authenticate_api, only: [:show], raise: false

  def show
    @token = params[:token]
    return render(json: {error: "not_found_or_expired"}, status: :not_found) unless Preview.verify(@token)

    @draft = Preview.read(@token)
    @page_id = Preview.page_id_for(@token)
    @page = @page_id && Page.find_by(id: @page_id)
  end

  # Mint a token tied to a page; persist initial draft state.
  def create
    # `page_slug` carries the full path now; older callers may still send a
    # leaf slug. Try path first, fall back to slug for backward compat.
    key = params.require(:page_slug)
    @page = Page.find_by(path: key) || Page.find_by!(slug: key)
    @issued = Preview.issue(page_id: @page.id)

    Preview.write(@issued[:token], preview_state_params.merge(page_id: @page.id))
  end

  # Update the cached draft for an existing token.
  def update
    token = params[:token]
    raise ActiveRecord::RecordNotFound unless Preview.verify(token)

    Preview.write(token, preview_state_params.merge(page_id: Preview.page_id_for(token)))
  end

  private

  def preview_state_params
    params.permit(:title, blocks: [:id, :type, :version, {data: {}}])
      .to_h
      .merge(
        frontmatter: deep_unwrap(params[:frontmatter]) || {},
        seo:         deep_unwrap(params[:seo]) || {}
      )
  end

  def deep_unwrap(value)
    case value
    when ActionController::Parameters then deep_unwrap(value.to_unsafe_h)
    when Array                        then value.map { |v| deep_unwrap(v) }
    when Hash                         then value.transform_values { |v| deep_unwrap(v) }
    else value
    end
  end
end

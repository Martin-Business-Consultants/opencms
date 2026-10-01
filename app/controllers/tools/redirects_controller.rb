# frozen_string_literal: true

# Tools › Redirects: a list table, with New and Edit in a sheet beside it
# (their forms load into its frame; visited on their own, or refused, the list
# opens with the sheet). Import, export and bulk delete are their own
# resources under Tools::Redirects.
class Tools::RedirectsController < ApplicationController
  requires_capability "redirects:read",   only: :index
  requires_capability "redirects:write",  only: [:new, :create, :edit, :update]
  requires_capability "redirects:delete", only: :destroy

  before_action :set_redirect, only: [:edit, :update, :destroy]

  def index
    @redirects = paginate(Redirect.ordered.search_list(search_term))
  end

  def new
    @redirect = Redirect.new(status_code: 301, active: true)
    in_sheet
  end

  def create
    @redirect = Redirect.new(redirect_params)

    if @redirect.save
      @redirect.track_event(:created, source: @redirect.source_path)
      redirect_to tools_redirects_path, notice: "Redirect created"
    else
      in_sheet(status: :unprocessable_content)
    end
  end

  def edit
    in_sheet
  end

  def update
    if @redirect.update(redirect_params)
      @redirect.track_event(:updated, source: @redirect.source_path)
      redirect_to tools_redirects_path, notice: "Redirect saved"
    else
      in_sheet(status: :unprocessable_content)
    end
  end

  def destroy
    @redirect.track_event(:deleted, source: @redirect.source_path)
    @redirect.destroy!
    redirect_to tools_redirects_path, notice: "Redirect deleted"
  end

  private

  # Into the sheet's frame when it asked; otherwise the list, the sheet open
  # with the redirect in it.
  def in_sheet(status: :ok)
    return if turbo_frame_request? && status == :ok

    @sheet_redirect = @redirect
    index
    render :index, status: status
  end

  def set_redirect
    @redirect = Redirect.find(params[:id])
  end

  def redirect_params
    params.require(:redirect).permit(:source_path, :destination_url, :status_code, :active, :notes)
  end
end

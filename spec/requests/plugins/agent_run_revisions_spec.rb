# frozen_string_literal: true

require "rails_helper"

# A revision knows the agent run that proposed it (revisions.agent_run_id),
# so a run's page lists exactly what it filed for review.
RSpec.describe "An agent run's revisions", type: :request do
  before do
    switch_plugin :ai, on: true
    switch_plugin :agents, on: true
  end

  let(:admin) { create(:user) }
  let(:agent) { Agent.create!(name: "Sweep", instructions: "Look.", capability_keys: %w[read_pages write_pages]) }
  let(:run) { agent.dispatch!.tap { it.update_columns(status: "running", started_at: 1.hour.ago) } }

  def published(slug) = Page.create!(slug: slug, title: slug.titleize, status: "published", locale: "en")

  it "links an in-process proposal to its run and lists it on the run's page" do
    published("history")

    Agents::Tools::UpdatePage.new(run).call("path" => "history", "title" => "Our history")

    revision = Revision.sole
    expect(revision).to have_attributes(source: "agent", agent_run: run)
    expect(run.revisions).to eq([revision])

    sign_in_as admin
    get agent_run_path(run)
    expect(response.body).to include(revision_path(revision))
  end

  it "links an API proposal that names the run, and only a run that exists" do
    published("team")
    published("contact")
    writer = create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write]))
    headers = {"Authorization" => "Bearer #{writer.api_token.token}"}

    patch "/api/pages/team", params: {page: {title: "Our team"}, agent_run_id: run.id}, headers: headers, as: :json
    patch "/api/pages/contact", params: {page: {title: "Contact us"}, agent_run_id: 999_999}, headers: headers, as: :json

    expect(response).to have_http_status(:accepted)
    expect(Revision.order(:id).map(&:agent_run_id)).to eq([run.id, nil])
  end

  it "still lists an older, unlinked API proposal made while the run was open" do
    page = published("about")
    older = Revision.propose!(record: page, attributes: {title: "About us"}, source: "api")
    unrelated = Revision.propose!(record: published("faq"), attributes: {title: "FAQ"}, source: "api")
    unrelated.update_columns(created_at: 2.days.ago)

    sign_in_as admin
    get agent_run_path(run)

    expect(response.body).to include(revision_path(older))
    expect(response.body).not_to include(revision_path(unrelated))
  end

  it "keeps the revision when its run goes" do
    published("history")
    Agents::Tools::UpdatePage.new(run).call("path" => "history", "title" => "Our history")

    run.destroy!

    expect(Revision.sole.agent_run_id).to be_nil
  end
end

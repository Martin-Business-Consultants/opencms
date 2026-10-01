# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AuditLogs", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as user }

  it "renders the audit log index" do
    AuditLog.record(action: "page.created", actor: user)
    get audit_logs_url
    expect(response).to have_http_status(:success)
  end

  it "instruments page deletion via the audit helper" do
    Page.create!(slug: "scratch", title: "Scratch", status: "draft", locale: "en",
                 blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {})

    expect {
      delete page_url("scratch")
    }.to change { AuditLog.where(action: "page.deleted").count }.by(1)

    log = AuditLog.where(action: "page.deleted").last
    expect(log.actor_id).to eq(user.id)
    expect(log.target_label).to eq("Scratch")
  end

  it "blocks readers without the audit_log:read capability" do
    reader_role = create(:role, permissions: ["pages:read"])
    reader      = create(:user, admin: false, role: reader_role)
    sign_in_as reader

    get audit_logs_url
    expect(response).to redirect_to(dashboard_path)
  end
end

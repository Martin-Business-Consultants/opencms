# frozen_string_literal: true

require "rails_helper"

# Jobs renamed to the _later/_now pattern keep their old class for one release,
# so a job already queued under the old name still runs. Remove with them.
RSpec.describe "Renamed jobs" do
  {
    "AgentRunJob" => AgentRun::ExecutionJob,
    "AgentSchedulerJob" => Agent::ScheduleJob,
    "ReapAgentRunsJob" => AgentRun::ReapJob,
    "NotifyFormSubmissionJob" => FormSubmission::NotificationJob,
    "NotifyQuoteRequestJob" => QuoteRequest::NotificationJob,
    "SendInvoiceJob" => Invoice::DeliveryJob,
    "AstroImportJob" => Importers::AstroJob,
    "DirectusImportJob" => Importers::DirectusJob,
    "WordpressImportJob" => Importers::WordpressJob
  }.each do |old_name, job|
    it "still runs #{old_name} as #{job}" do
      expect(old_name.constantize.superclass).to eq(job)
    end
  end

  it "delivers an invoice queued under the old name, tenant argument and all" do
    invoice = Invoice.create!(customer_name: "Ann", customer_email: "ann@x.test",
      line_items: [{"description" => "Work", "quantity" => 1, "unit_price_cents" => 1000}])

    expect { SendInvoiceJob.perform_now(invoice.id, "acme", "https://site.test") }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
  end
end

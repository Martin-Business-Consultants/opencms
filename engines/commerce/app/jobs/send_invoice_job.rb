# frozen_string_literal: true

# Renamed to Invoice::DeliveryJob. Kept one release so jobs queued under the
# old name still run; remove after.
class SendInvoiceJob < Invoice::DeliveryJob
end

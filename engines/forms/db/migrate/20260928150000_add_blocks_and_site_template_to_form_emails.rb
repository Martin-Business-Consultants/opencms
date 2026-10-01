# frozen_string_literal: true

# A form email's content as blocks (FormEmail::Content), and the template the
# Astro site built from them (FormEmail::SiteTemplate): its HTML, the digest
# of the blocks it was built from, and when it arrived.
class AddBlocksAndSiteTemplateToFormEmails < ActiveRecord::Migration[8.1]
  def change
    add_column :form_emails, :blocks, :json, default: [], null: false
    add_column :form_emails, :site_template, :text
    add_column :form_emails, :site_template_digest, :string
    add_column :form_emails, :site_template_received_at, :datetime
  end
end

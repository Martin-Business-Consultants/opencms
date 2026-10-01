# frozen_string_literal: true

# What the email editor posts, read back: its settings, and its blocks
# through ContentForm against FormEmail::BlockTypes.
module FormEmails::Editing
  extend ActiveSupport::Concern

  included do
    before_action { @form = Form.find_by!(slug: params[:form_slug]) }
  end

  private

  def email_attributes(email)
    attributes = params.require(:form_email).permit(:enabled, :subject, :from_field, :recipients).to_h
    raw = params.dig(:form_email, :blocks)
    attributes["blocks"] = ContentForm.blocks(raw, block_types: FormEmail::BlockTypes.by_slug) unless raw.nil?
    attributes
  end
end

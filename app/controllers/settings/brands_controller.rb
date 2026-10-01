# frozen_string_literal: true

# Settings → Brand context. A short brief describing how this workspace
# wants its content written: voice, who it's for, facts that must stay
# accurate, and house style rules.
#
# Nothing in the CMS renders it. It exists to be *read* — `/api/manifest`
# publishes it, so an agent driving the CMS from the outside (Claude Code,
# Codex, …) writes in the workspace's voice instead of a generic one.
#
# Distinct from Settings → Branding (`Settings::BrandingsController`), which
# is the visual side: logo, colors, fonts.
class Settings::BrandsController < Settings::BaseController
  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :update

  SETTING_KEY = BrandBrief::SETTING_KEY

  FIELDS = BrandBrief::FIELDS

  # Each field's label and hint on the form.
  LABELS = {
    "brand_voice" => ["Voice", "How the writing should sound. Concrete adjectives beat abstract ones."],
    "audience"    => ["Audience", "Who is reading, and what they already know."],
    "key_facts"   => ["Key facts", "Details that must stay accurate — names, numbers, claims that can't be invented."],
    "style_notes" => ["Style notes", "House rules. Do's and don'ts, spellings, words to avoid."]
  }.freeze

  def show
    data = Setting.get(SETTING_KEY)
    @settings = FIELDS.index_with { |field| data[field].to_s }
  end

  def update
    # Overwrite rather than merge, so clearing a field in the form actually
    # clears it. `Setting.set` deep-merges, which would strand old text.
    @record = Setting.find_or_initialize_by(key: SETTING_KEY)
    @record.data = settings_params.to_h.slice(*FIELDS).transform_values { |v| v.to_s.strip }

    if @record.save
      Event.record("settings.brand_updated", fields_set: @record.data.reject { |_, v| v.empty? }.keys.sort)
      redirect_to settings_brand_path, notice: "Brand context saved"
    else
      @settings = @record.data
      render :show, status: :unprocessable_content
    end
  end

  private

  def settings_params
    params.require(:settings).permit(*FIELDS)
  end
end

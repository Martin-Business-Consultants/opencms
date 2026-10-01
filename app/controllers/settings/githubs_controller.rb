# frozen_string_literal: true

# Settings → GitHub. Personal access token used by anything in the app that
# needs to talk to the GitHub API — currently the Astro importer — plus
# `frontend_github_repo`, the repo holding the Astro site this CMS
# publishes. The two belong together: the repo names what to clone, the token
# is what clones it. AI agents read the repo to know where to do site work.
class Settings::GithubsController < Settings::BaseController
  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :update

  SETTING_KEY = "github"

  def show
    data = Setting.get(SETTING_KEY)
    # Never round-trip the raw token; just whether one is set + last 4.
    @token_hint = data["token"].to_s[-4..]
    @frontend_github_repo = data["frontend_github_repo"].to_s
  end

  def update
    incoming = settings_params.to_h
    # Empty token in the form means "leave the existing one alone".
    incoming.delete("token") if incoming["token"].to_s.empty?

    # A blank repo, by contrast, is a real value — it's how you clear one that
    # was set wrong — so it's only dropped when the form didn't submit it.
    if incoming.key?("frontend_github_repo")
      incoming["frontend_github_repo"] = incoming["frontend_github_repo"].to_s.strip
    end

    Setting.set(SETTING_KEY, incoming)
    Event.record("settings.github_updated", token_changed: incoming.key?("token"), frontend_github_repo: incoming["frontend_github_repo"])
    redirect_to settings_github_path, notice: "GitHub settings saved"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_github_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def settings_params
    params.require(:settings).permit(:token, :frontend_github_repo)
  end
end

# frozen_string_literal: true

module UpdatesHelper
  def update_method_description
    case Upgrade.via
    when "hoster" then "A deploy proposed to Hoster (#{Upgrade::Hoster.url.presence || "CMS_HOSTER_URL unset"}), approved there"
    when "github"
      destination = Upgrade::Github.destination.presence
      "The Deploy workflow on GitHub (#{UpdateCheck.repo}#{", destination #{destination}" if destination})"
    when "local" then "bin/update on this server"
    else "By hand: updating from here isn’t set up"
    end
  end

  # What to run by hand when the button isn't set up: bin/update in a plain
  # install's checkout, else Kamal from a checkout of the release.
  def manual_update_command(tag)
    if Rails.root.join(".git").exist?
      "bin/update #{tag}"
    else
      "git checkout #{tag} && bin/kamal deploy -d #{Upgrade::Github.destination.presence || "<destination>"}"
    end
  end

  # Where a running update can be followed, named for where it runs.
  def upgrade_follow_text(upgrade)
    case upgrade.via
    when "hoster" then upgrade.runner.awaiting_approval? ? "Approve the deploy in Hoster" : "Follow the deploy in Hoster"
    when "github" then "Follow the deploy on GitHub"
    else "Follow the update"
    end
  end

  def upgrade_requester(upgrade)
    upgrade.requested_by&.name.presence || upgrade.requested_by&.email || "someone since removed"
  end
end

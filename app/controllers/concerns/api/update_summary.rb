# frozen_string_literal: true

# The agent envelope's one line for GET /api/updates and POST
# /api/updates/check, which answer in the same shape.
module Api::UpdateSummary
  private

  def update_summary(updates)
    running = updates["past_updates"].find { it["status"] == "running" }
    if running
      "Updating from #{running["from_version"]} to #{running["to_version"]}."
    elsif updates["update_available"]
      how = updates["not_set_up_because"] ? "updating from the admin isn't set up" : "an admin can install it from Settings › Updates"
      "CMS #{updates["version"]}; #{updates["latest_release"]["version"]} is out, and #{how}."
    else
      "CMS #{updates["version"]} is the newest release#{" (never checked)" unless updates["checked_at"]}."
    end
  end
end

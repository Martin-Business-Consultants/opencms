# frozen_string_literal: true

# Updates a plain install (bin/install) by running `bin/update <tag>` in the
# background, as the app's own user: back up the data directory, fetch and
# check out the release, bundle, migrate, compile assets, restart Puma. Its
# output and exit status go to updates/<id>/ in the data directory
# (CMS_DATA_DIR). The checkout must belong to that user and be able to fetch
# from the repository.
class Upgrade::Local
  def initialize(upgrade)
    @upgrade = upgrade
  end

  # Its own process group, so Puma restarting under it doesn't take it down.
  # The paths are worked out before Bundler's environment is dropped, which
  # resets ENV to what the process started with.
  def start
    FileUtils.mkdir_p directory
    arguments = [@upgrade.tag, log.to_s, exit_status.to_s]
    Bundler.with_unbundled_env do
      pid = Process.spawn("/bin/bash", "-c", %(bin/update "$1" > "$2" 2>&1; echo $? > "$3"), "update", *arguments,
        chdir: Rails.root.to_s, pgroup: true, in: File::NULL, out: File::NULL, err: File::NULL)
      Process.detach(pid)
    end
  end

  # bin/update finished: a non-zero exit fails the upgrade with the end of
  # its output. A zero exit waits for Puma to come back on the new version.
  def check
    if exit_status.exist?
      code = exit_status.read.strip
      @upgrade.fail_with "bin/update stopped (exit #{code}):\n#{log_tail}" unless code == "0"
    end
  end

  # A run that hasn't settled within Upgrade::TIMEOUT of the ask has gone quiet.
  def timing_out_since = @upgrade.created_at

  def where_to_look = "Its output is in #{log}."

  private

  def directory = Cms.data_dir.join("updates", @upgrade.id.to_s)
  def log = directory.join("update.log")
  def exit_status = directory.join("exit_status")

  def log_tail = log.exist? ? log.readlines.last(20).join : "(no output)"
end

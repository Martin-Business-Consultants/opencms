# frozen_string_literal: true

require "fileutils"
require "net/http"
require "uri"
require "rubygems/package"
require "zlib"

module Astro
  # Downloads a GitHub repo's tarball for the given ref and extracts it
  # under `dest_dir`. Returns the path to the extracted root directory
  # (which GitHub names `<owner>-<repo>-<sha>`).
  #
  # Public repos work without a token; private repos require one with the
  # `repo` scope. Token comes from Setting.get("github")["token"].
  class Fetcher
    class Error < StandardError; end

    HOST = "api.github.com"

    Repo = Struct.new(:owner, :name, keyword_init: true)

    def initialize(repo_url:, ref: "main", token: nil)
      @repo  = self.class.parse_repo(repo_url)
      @ref   = ref.presence || "main"
      @token = token.presence
      raise Error, "Could not parse GitHub repo URL: #{repo_url.inspect}" unless @repo
    end

    # Download and extract. Returns the absolute path to the extracted dir.
    def fetch(dest_dir)
      FileUtils.mkdir_p(dest_dir)
      tarball_path = File.join(dest_dir, "repo.tar.gz")

      download_to(tarball_path)
      extract_to(tarball_path, dest_dir)

      root = Dir.children(dest_dir).map { |c| File.join(dest_dir, c) }
              .find { |p| File.directory?(p) && File.basename(p).match?(/\A#{Regexp.escape(@repo.owner)}-#{Regexp.escape(@repo.name)}-/i) }
      raise Error, "Tarball didn't contain the expected #{@repo.owner}-#{@repo.name}-* directory" unless root

      root
    ensure
      File.delete(tarball_path) if tarball_path && File.exist?(tarball_path)
    end

    # Parse owner/name out of a github URL. Accepts:
    #   https://github.com/owner/repo
    #   https://github.com/owner/repo.git
    #   git@github.com:owner/repo.git
    def self.parse_repo(url)
      s = url.to_s.strip
      m = s.match(%r{github\.com[:/]([\w.\-]+)/([\w.\-]+?)(?:\.git)?/?\z})
      return nil unless m

      Repo.new(owner: m[1], name: m[2])
    end

    private

    def download_to(path)
      uri = URI.parse("https://#{HOST}/repos/#{@repo.owner}/#{@repo.name}/tarball/#{@ref}")
      follow_redirects(uri, max: 5) do |io|
        File.binwrite(path, io.read)
      end
    end

    def follow_redirects(uri, max:, &block)
      raise Error, "Too many redirects fetching #{uri}" if max.negative?

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["User-Agent"]    = "mbc-cms-astro-importer"
        req["Accept"]        = "application/vnd.github+json"
        req["Authorization"] = "Bearer #{@token}" if @token

        http.request(req) do |res|
          case res
          when Net::HTTPRedirection
            follow_redirects(URI.parse(res["location"]), max: max - 1, &block)
          when Net::HTTPSuccess
            yield res
          when Net::HTTPNotFound
            raise Error, "GitHub returned 404 — check repo URL and ref (#{@ref}). " \
                         "If this is a private repo, set a token in Settings → Astro."
          when Net::HTTPUnauthorized, Net::HTTPForbidden
            raise Error, "GitHub returned #{res.code} — token missing or insufficient scope (needs `repo`)."
          else
            raise Error, "GitHub returned #{res.code}: #{res.message}"
          end
        end
      end
    end

    def extract_to(tarball_path, dest_dir)
      File.open(tarball_path, "rb") do |gz_io|
        Zlib::GzipReader.wrap(gz_io) do |tar_io|
          Gem::Package::TarReader.new(tar_io) do |tar|
            tar.each do |entry|
              relative = sanitize_path(entry.full_name)
              next if relative.nil? || relative.empty?

              target = File.join(dest_dir, relative)
              if entry.directory?
                FileUtils.mkdir_p(target)
              elsif entry.file?
                FileUtils.mkdir_p(File.dirname(target))
                File.binwrite(target, entry.read)
              end
            end
          end
        end
      end
    end

    # Defend against tar paths that try to escape the dest dir.
    def sanitize_path(name)
      cleaned = name.to_s.gsub(/\A\.+\/+/, "")
      return nil if cleaned.split("/").any? { |part| part == ".." }

      cleaned
    end
  end
end

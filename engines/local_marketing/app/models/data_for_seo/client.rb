# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Thin transport for the DataForSEO v3 API.
#
# DataForSEO is not REST. Every endpoint is a POST, the body is always an
# ARRAY of task objects (even for one task), and the HTTP status is 200 for
# most failures — the real outcome lives in `status_code` at two levels:
# once for the request, once per task. 20000 means OK in both places. A
# client that only checks `Net::HTTPSuccess` reports a quota exhaustion, a
# bad credential and an empty result as the same silent success, so this
# raises on all three.
#
# Credentials live in `Setting` (encrypted), not in ENV: they belong to the site and are set in the admin.
# One agency's DataForSEO account bills for one agency's sites.
module DataForSeo
  class Client
    SETTING_KEY = "reporting"

    HOST         = "api.dataforseo.com"
    SANDBOX_HOST = "sandbox.dataforseo.com"

    OK = 20_000
    # A task-based endpoint answers task_post with "created", and task_get
    # with one of these until the work is done. Neither is an error.
    TASK_CREATED = 20_100
    TASK_IN_PROGRESS = [40_601, 40_602].freeze # handed to a worker / in queue

    # Live endpoints in this API are genuinely slow — `target_metrics` is
    # documented at up to 120s — so the read timeout is generous and the
    # open timeout is not. A hung TCP connect is a different failure from a
    # long-running query and shouldn't wait two minutes to say so.
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 180

    attr_reader :sandbox

    def self.configured?
      Setting.secret(SETTING_KEY, :dataforseo_login).present? &&
        Setting.secret(SETTING_KEY, :dataforseo_password).present?
    end

    # Builds a client from the site's settings row. Raises rather than
    # returning nil — see NotConfigured.
    def self.from_settings
      login    = Setting.secret(SETTING_KEY, :dataforseo_login)
      password = Setting.secret(SETTING_KEY, :dataforseo_password)

      if login.blank? || password.blank?
        raise NotConfigured, "No DataForSEO credentials. Add them in Settings → Reporting."
      end

      new(login: login, password: password, sandbox: Setting.get(SETTING_KEY)["sandbox"].present?)
    end

    def initialize(login:, password:, sandbox: false)
      @login = login
      @password = password
      @sandbox = sandbox
    end

    def host = sandbox ? SANDBOX_HOST : HOST

    # POST one task to `path` and return its result.
    #
    # `path` is the part after /v3, e.g.
    # "dataforseo_labs/google/ranked_keywords/live".
    def post(path, task)
      body = request(path, [task.compact])
      envelope_ok!(body)

      task_body = Array(body["tasks"]).first
      raise Error, "DataForSEO returned no task for #{path}" if task_body.nil?

      task_ok!(task_body, path)

      Response.new(
        result:  Array(task_body["result"]),
        cost:    task_body["cost"].to_f,
        task_id: task_body["id"],
        time:    task_body["time"]
      )
    end

    # POST several tasks in one call. DataForSEO bills per task either way,
    # but one HTTP round trip for twenty keywords is the difference between
    # a report that renders and one that times out.
    #
    # Tasks that fail individually are returned as nil in place, so the
    # caller can keep the correspondence with what it sent rather than
    # having to guess which of twenty keywords came back.
    def post_many(path, tasks)
      return [] if tasks.empty?

      body = request(path, tasks.map(&:compact))
      envelope_ok!(body)

      Array(body["tasks"]).map do |task_body|
        next nil unless task_body["status_code"].to_i == OK

        Response.new(
          result:  Array(task_body["result"]),
          cost:    task_body["cost"].to_f,
          task_id: task_body["id"],
          time:    task_body["time"]
        )
      end
    end

    # Cheapest possible round trip that proves the credential works. Used by
    # the "Test connection" button, and it returns the account's balance
    # because "the key works" and "the key has money behind it" are two
    # different questions a person is really asking.
    def ping
      body = request("appendix/user_data", nil, method: :get)
      envelope_ok!(body)

      info = Array(body["tasks"]).first&.dig("result")&.first || {}
      {
        login:   info.dig("login"),
        balance: info.dig("money", "balance"),
        limit:   info.dig("rates", "limits", "minute")
      }
    end

    # ---- task-based endpoints ----------------------------------------------
    #
    # A few endpoints (Google reviews among them) don't answer live: you post
    # a task, DataForSEO works it in the background, and you fetch the result
    # when it's ready. The billing happens at post time, so a caller that
    # posts and gives up has still paid — see Reports::Definition#await_task.

    # POST one task and return its id. `path` is the endpoint base, e.g.
    # "business_data/google/reviews" — "/task_post" is appended.
    def post_task(path, task)
      body = request("#{path}/task_post", [task.compact])
      envelope_ok!(body)

      task_body = Array(body["tasks"]).first
      raise Error, "DataForSEO returned no task for #{path}" if task_body.nil?

      code = task_body["status_code"].to_i
      unless [OK, TASK_CREATED].include?(code)
        raise Error.new("DataForSEO task_post for #{path} failed (#{code}): #{task_body["status_message"]}",
                        status_code: code, status_message: task_body["status_message"])
      end

      {id: task_body["id"].to_s, cost: task_body["cost"].to_f}
    end

    # GET a task's result. Returns a Response when it's done, **nil** while it
    # is still being worked, and raises on anything else — so the caller's
    # loop is `until (r = task_get(...))`.
    def task_get(path, id)
      body = request("#{path}/task_get/#{id}", nil, method: :get)
      envelope_ok!(body)

      task_body = Array(body["tasks"]).first
      raise Error, "DataForSEO returned no task for #{path}/#{id}" if task_body.nil?

      code = task_body["status_code"].to_i
      return nil if TASK_IN_PROGRESS.include?(code)

      task_ok!(task_body, path)
      Response.new(result: Array(task_body["result"]), cost: task_body["cost"].to_f,
                   task_id: task_body["id"], time: task_body["time"])
    end

    # A GET against a reference endpoint — the locations/languages lists and
    # the like. Reference data, so no task envelope to unwrap: the result
    # array is the answer.
    def get(path)
      body = request(path, nil, method: :get)
      envelope_ok!(body)

      task_body = Array(body["tasks"]).first
      raise Error, "DataForSEO returned no task for #{path}" if task_body.nil?

      task_ok!(task_body, path)
      Array(task_body["result"])
    end

    private

    def request(path, payload, method: :post)
      uri = URI::HTTPS.build(host: host, path: "/v3/#{path}")

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        req = build_request(method, uri, payload)
        http.request(req)
      end

      # 401 never carries a JSON envelope, so it has to be caught here.
      if response.is_a?(Net::HTTPUnauthorized)
        raise NotConfigured, "DataForSEO rejected the credentials (401). Check the login and password in Settings → Reporting."
      end

      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise Error, "DataForSEO returned a non-JSON response (HTTP #{response&.code})"
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "DataForSEO timed out after #{READ_TIMEOUT}s (#{e.class})"
    end

    def build_request(method, uri, payload)
      req =
        if method == :get
          Net::HTTP::Get.new(uri.request_uri)
        else
          Net::HTTP::Post.new(uri.request_uri).tap { |r| r.body = JSON.generate(payload) }
        end

      req.basic_auth(@login, @password)
      req["Content-Type"] = "application/json"
      req["User-Agent"]   = "librepublish-cms-reporting/1"
      req
    end

    # Request-level status. 40200-odd here is usually money or rate limit,
    # which is worth saying plainly rather than surfacing a bare number.
    def envelope_ok!(body)
      code = body["status_code"].to_i
      return if code == OK

      raise Error.new(
        "DataForSEO error #{code}: #{body["status_message"]}",
        status_code: code, status_message: body["status_message"]
      )
    end

    def task_ok!(task_body, path)
      code = task_body["status_code"].to_i
      return if code == OK

      raise Error.new(
        "DataForSEO task for #{path} failed (#{code}): #{task_body["status_message"]}",
        status_code: code, status_message: task_body["status_message"]
      )
    end
  end
end

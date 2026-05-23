require "net/http"
require "uri"
require "rubygems/version"

module Neuz
  # Polls GitHub for a newer version. Designed to never block a request:
  # the public API returns whatever is in the cache (possibly nil) and
  # spawns a background refresh when the cache is stale. All network
  # failures are swallowed.
  module UpdateCheck
    module_function

    TTL_SECONDS = 3600
    HTTP_TIMEOUT = 3
    DEFAULT_BRANCH = "main".freeze
    DEFAULT_FILE = "VERSION".freeze

    CACHE = { latest: nil, checked_at: Time.at(0), refreshing: false }
    LOCK = Mutex.new

    # Returns the latest known upstream version string, or nil if we
    # haven't successfully fetched one yet. Kicks off an async refresh
    # when the cache is stale.
    def latest_version
      return nil if Config.test?

      maybe_refresh_async
      LOCK.synchronize { CACHE[:latest] }
    end

    # True if the upstream version is strictly greater than the running
    # version. Returns false (not nil) when we don't know yet, so views
    # can treat it as a simple boolean.
    def update_available?
      latest = latest_version
      return false unless latest && !latest.empty?

      Gem::Version.new(latest) > Gem::Version.new(Neuz.version)
    rescue ArgumentError
      false
    end

    # Build the raw.githubusercontent.com URL for the configured repo.
    # Returns nil if the configured repo_url isn't a parseable GitHub URL.
    def raw_version_url
      uri = URI.parse(Config.repo_url)
      return nil unless uri.host&.end_with?("github.com")

      path = uri.path.to_s.sub(%r{\A/}, "").sub(%r{\.git\z}, "")
      owner, repo = path.split("/", 2)
      return nil if owner.to_s.empty? || repo.to_s.empty?

      "https://raw.githubusercontent.com/#{owner}/#{repo}/#{DEFAULT_BRANCH}/#{DEFAULT_FILE}"
    rescue URI::InvalidURIError
      nil
    end

    def reset_for_test!
      LOCK.synchronize do
        CACHE[:latest] = nil
        CACHE[:checked_at] = Time.at(0)
        CACHE[:refreshing] = false
      end
    end

    class << self
      private

      def maybe_refresh_async
        now = Time.now.utc
        should_refresh = LOCK.synchronize do
          next false if CACHE[:refreshing]
          next false if now - CACHE[:checked_at] < TTL_SECONDS

          CACHE[:refreshing] = true
          true
        end
        return unless should_refresh

        Thread.new { refresh! }
      end

      def refresh!
        latest = fetch_remote_version
        LOCK.synchronize do
          CACHE[:latest] = latest if latest
          CACHE[:checked_at] = Time.now.utc
          CACHE[:refreshing] = false
        end
      end

      def fetch_remote_version
        url = raw_version_url
        return nil unless url

        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = HTTP_TIMEOUT
        http.read_timeout = HTTP_TIMEOUT

        req = Net::HTTP::Get.new(uri.request_uri)
        req["User-Agent"] = "Neuz/#{Neuz.version}"

        res = http.request(req)
        return nil unless res.is_a?(Net::HTTPSuccess)

        parse_version(res.body)
      rescue StandardError, Timeout::Error
        nil
      end

      def parse_version(body)
        line = body.to_s.lines.find { |l| l.strip != "" }
        return nil unless line

        v = line.strip.sub(/\Av/i, "")
        v.match?(/\A\d+(\.\d+)*\z/) ? v : nil
      end
    end
  end
end

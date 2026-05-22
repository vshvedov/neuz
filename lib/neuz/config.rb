require "fileutils"
require "securerandom"

module Neuz
  module Config
    module_function

    def root
      @root ||= File.expand_path("../..", __dir__)
    end

    def data_dir
      ENV["NEUZ_DATA_DIR"] || File.join(root, "data")
    end

    def public_dir
      File.join(root, "public")
    end

    def prompts_dir
      File.join(root, "prompts")
    end

    def views_dir
      File.join(root, "app", "views")
    end

    def migrations_dir
      File.join(root, "db", "migrations")
    end

    def database_path
      ENV["NEUZ_DB_PATH"] || File.join(data_dir, "neuz.db")
    end

    def database_url
      "sqlite://#{database_path}"
    end

    def first_boot_key_path
      File.join(data_dir, "first_boot_key.txt")
    end

    def rate_capacity
      Integer(ENV.fetch("NEUZ_RATE_CAPACITY", "60"))
    end

    def rate_refill_per_min
      Integer(ENV.fetch("NEUZ_RATE_REFILL_PER_MIN", "60"))
    end

    def rate_refill_per_sec
      rate_refill_per_min / 60.0
    end

    def prune_days
      Integer(ENV.fetch("NEUZ_PRUNE_DAYS", "90"))
    end

    def prune_interval_seconds
      Integer(ENV.fetch("NEUZ_PRUNE_INTERVAL_SECONDS", "3600"))
    end

    def journal_mode
      mode = ENV.fetch("NEUZ_JOURNAL_MODE", "WAL").upcase
      %w[WAL DELETE].include?(mode) ? mode : "WAL"
    end

    def cache_size
      Integer(ENV.fetch("NEUZ_CACHE_SIZE", "-20000"))
    end

    def mmap_size
      Integer(ENV.fetch("NEUZ_MMAP_SIZE", "67108864"))
    end

    def batch_limit
      Integer(ENV.fetch("NEUZ_BATCH_LIMIT", "500"))
    end

    def public_url(request_base_url = nil)
      ENV["NEUZ_URL"] || request_base_url
    end

    def brand
      value = ENV["NEUZ_BRAND"].to_s.strip
      value.empty? ? "Neuz" : value
    end

    def tagline
      ENV["NEUZ_TAGLINE"].to_s.strip
    end

    def repo_url
      value = ENV["NEUZ_REPO_URL"].to_s.strip
      value.empty? ? "https://github.com/vshvedov/neuz" : value
    end

    def rack_env
      ENV["RACK_ENV"] || "production"
    end

    def production?
      rack_env == "production"
    end

    def test?
      rack_env == "test"
    end

    def ensure_data_dir!
      FileUtils.mkdir_p(data_dir, mode: 0o700)
    end
  end
end

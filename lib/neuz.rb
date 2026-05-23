Encoding.default_external = Encoding::UTF_8 if Encoding.default_external != Encoding::UTF_8
Encoding.default_internal ||= Encoding::UTF_8

require_relative "neuz/version"
require_relative "neuz/config"
require_relative "neuz/db"
require_relative "neuz/validators"
require_relative "neuz/auth"
require_relative "neuz/rate_limiter"
require_relative "neuz/ingest"
require_relative "neuz/prompts"
require_relative "neuz/prune"
require_relative "neuz/setup"
require_relative "neuz/update_check"
require_relative "neuz/app"

module Neuz
  module_function

  # Idempotent boot: ensures data dir exists, applies migrations,
  # mints the first API key if none exists, starts the prune daemon.
  # Called from config.ru on web start and from tests as needed.
  def boot!
    return if @booted
    Config.ensure_data_dir!
    DB.warn_if_networked_filesystem
    DB.connect!
    DB.migrate!
    ensure_first_api_key!
    Prune.start! if Config.prune_days.positive?
    @booted = true
  end

  def reset_for_test!
    @booted = false
    DB.disconnect!
    if defined?(App::CHIP_CACHE)
      App::CHIP_CACHE[:at] = Time.at(0)
      App::CHIP_CACHE[:data] = []
    end
    UpdateCheck.reset_for_test! if defined?(UpdateCheck)
  end

  def ensure_first_api_key!
    return if DB.connection[:api_keys].any?

    raw = SecureRandom.urlsafe_base64(32)
    digest = Auth.digest(raw)
    DB.connection[:api_keys].insert(
      user_id: 1,
      sha256: digest,
      label: "default",
      created_at: Time.now.utc,
    )
    File.binwrite(Config.first_boot_key_path, raw)
    File.chmod(0o600, Config.first_boot_key_path)
    raw
  end

  require "securerandom"
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

ENV["RACK_ENV"] = "test"

require "fileutils"
require "tmpdir"
require "securerandom"

TEST_DATA_DIR = Dir.mktmpdir("neuz-test-")
ENV["NEUZ_DATA_DIR"] = TEST_DATA_DIR
ENV["NEUZ_DB_PATH"] = File.join(TEST_DATA_DIR, "neuz-test.db")
ENV["NEUZ_PRUNE_DAYS"] = "0"

require "minitest/autorun"
require "rack/test"
require "json"
require "neuz"

at_exit { FileUtils.rm_rf(TEST_DATA_DIR) }

module Neuz
  module TestSupport
    include Rack::Test::Methods

    def app
      Neuz::App.freeze.app
    end

    def setup
      # Reset DB + state between tests by dropping & re-migrating.
      Neuz.reset_for_test!
      path = ENV["NEUZ_DB_PATH"]
      File.delete(path) if File.exist?(path)
      File.delete("#{path}-wal") if File.exist?("#{path}-wal")
      File.delete("#{path}-shm") if File.exist?("#{path}-shm")
      File.delete(Neuz::Config.first_boot_key_path) if File.exist?(Neuz::Config.first_boot_key_path)
      Neuz.instance_variable_set(:@booted, false)
      Neuz.boot!
    end

    def teardown
      Neuz.reset_for_test!
    end

    def first_boot_key
      File.binread(Neuz::Config.first_boot_key_path)
    end

    def bearer(key)
      { "HTTP_AUTHORIZATION" => "Bearer #{key}" }
    end

    def post_json(path, body, env = {})
      post path, body.to_json, env.merge("CONTENT_TYPE" => "application/json")
    end

    def json_response
      JSON.parse(last_response.body)
    end
  end
end

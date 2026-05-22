require_relative "test_helper"

class SetupCLITest < Minitest::Test
  include Neuz::TestSupport

  def test_prepare_returns_first_boot_raw_key
    raw = Neuz::Setup.prepare!
    refute_nil raw
    assert_equal raw, File.binread(Neuz::Config.first_boot_key_path)
  end

  def test_banner_includes_key_and_prompts
    raw = Neuz::Setup.prepare!
    out = Neuz::Setup.banner(url: "http://example.local", raw_key: raw)
    assert_includes out, raw
    assert_includes out, "http://example.local"
    assert_includes out, "INTERVIEW PROMPT"
    assert_includes out, "RECURRING PROMPT"
    refute_includes out, "{{NEUZ_API_KEY}}"
    refute_includes out, "{{NEUZ_URL}}"
  end

  def test_banner_without_key_when_acknowledged
    raw = Neuz::Setup.prepare!
    Neuz::Setup.acknowledge!
    out = Neuz::Setup.banner(url: "http://x", raw_key: nil, acknowledged: true)
    refute_includes out, raw
    assert_includes out, "already been acknowledged"
    assert_includes out, "bin/neuz rotate"
  end

  def test_acknowledge_deletes_the_file_and_records_setting
    Neuz::Setup.prepare!
    assert File.exist?(Neuz::Config.first_boot_key_path)
    assert Neuz::Setup.acknowledge!
    refute File.exist?(Neuz::Config.first_boot_key_path)
    assert Neuz::Setup.acknowledged?
  end

  def test_acknowledge_is_idempotent
    Neuz::Setup.prepare!
    Neuz::Setup.acknowledge!
    refute Neuz::Setup.acknowledge! # already gone
  end

  def test_rotate_invalidates_old_key
    old_raw = Neuz::Setup.prepare!
    new_raw = Neuz::Setup.rotate!
    refute_equal old_raw, new_raw
    assert_equal new_raw, File.binread(Neuz::Config.first_boot_key_path)

    # Old key no longer authenticates
    post_json "/api/items", { items: [] }, bearer(old_raw)
    assert_equal 401, last_response.status

    # New key works
    post_json "/api/items", { items: [] }, bearer(new_raw)
    assert_equal 200, last_response.status
  end

  def test_rotate_clears_acknowledged_marker
    Neuz::Setup.prepare!
    Neuz::Setup.acknowledge!
    assert Neuz::Setup.acknowledged?
    Neuz::Setup.rotate!
    refute Neuz::Setup.acknowledged?
  end

  def test_status_reports_key_file_present_flag
    Neuz::Setup.prepare!
    s = Neuz::Setup.status
    assert s[:key_file_present]
    refute s[:key_acknowledged]
    assert_kind_of Integer, s[:items_total]
    assert_match(/\A\d+\.\d+\.\d+\z/, s[:version])
  end

  def test_bin_neuz_prompts_with_explicit_key_after_ack
    raw = Neuz::Setup.prepare!
    Neuz::Setup.acknowledge!
    refute File.exist?(Neuz::Config.first_boot_key_path)

    env = {
      "NEUZ_DATA_DIR" => ENV["NEUZ_DATA_DIR"],
      "NEUZ_DB_PATH" => ENV["NEUZ_DB_PATH"],
      "RACK_ENV" => "test",
    }
    out = IO.popen(env, ["ruby", "-Ilib", File.expand_path("../bin/neuz", __dir__),
                         "prompts", "--key", raw, "--url", "http://x.test"], err: %i[child out], &:read)
    assert_predicate $?, :success?, "bin/neuz prompts --key failed: #{out}"
    assert_includes out, raw
    assert_includes out, "INTERVIEW PROMPT"
  end

  def test_bin_neuz_prompts_with_bad_key_refuses
    Neuz::Setup.prepare!
    Neuz::Setup.acknowledge!
    env = {
      "NEUZ_DATA_DIR" => ENV["NEUZ_DATA_DIR"],
      "NEUZ_DB_PATH" => ENV["NEUZ_DB_PATH"],
      "RACK_ENV" => "test",
    }
    out = IO.popen(env, ["ruby", "-Ilib", File.expand_path("../bin/neuz", __dir__),
                         "prompts", "--key", "bogus"], err: %i[child out], &:read)
    refute_predicate $?, :success?
    assert_includes out, "did not match"
  end

  def test_bin_neuz_status_runs_without_error
    env = {
      "NEUZ_DATA_DIR" => ENV["NEUZ_DATA_DIR"],
      "NEUZ_DB_PATH" => ENV["NEUZ_DB_PATH"],
      "RACK_ENV" => "test",
    }
    out = IO.popen(env, ["ruby", "-Ilib", File.expand_path("../bin/neuz", __dir__), "status"], err: %i[child out], &:read)
    assert_predicate $?, :success?, "bin/neuz status failed: #{out}"
    assert_includes out, "url"
    assert_includes out, "version"
  end
end

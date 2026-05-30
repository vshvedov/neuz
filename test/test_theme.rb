require_relative "test_helper"

class ThemeConfigTest < Minitest::Test
  include Neuz::TestSupport

  def with_env(name)
    old = ENV["NEUZ_THEME"]
    name.nil? ? ENV.delete("NEUZ_THEME") : ENV["NEUZ_THEME"] = name
    yield
  ensure
    old.nil? ? ENV.delete("NEUZ_THEME") : ENV["NEUZ_THEME"] = old
  end

  def test_theme_defaults_to_default
    with_env(nil) { assert_equal "default", Neuz::Config.theme }
  end

  def test_theme_reads_env_lowercased
    with_env("Gruvbox") { assert_equal "gruvbox", Neuz::Config.theme }
  end

  def test_theme_rejects_traversal_and_invalid
    with_env("../etc/passwd") { assert_equal "default", Neuz::Config.theme }
    with_env("a/b") { assert_equal "default", Neuz::Config.theme }
    with_env("") { assert_equal "default", Neuz::Config.theme }
  end

  def test_dirs_point_at_repo_and_data
    assert Neuz::Config.themes_dir.end_with?("/themes")
    assert Neuz::Config.custom_themes_dir.start_with?(Neuz::Config.data_dir)
  end

  def test_custom_themes_dir_created_on_boot
    assert Dir.exist?(Neuz::Config.custom_themes_dir)
  end
end

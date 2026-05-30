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

class ThemeLoaderTest < Minitest::Test
  include Neuz::TestSupport

  def teardown
    super
    custom = File.join(Neuz::Config.custom_themes_dir, "default.css")
    File.delete(custom) if File.exist?(custom)
    Neuz::Theme.reset_cache!
  end

  def test_builtin_theme_resolves
    css = Neuz::Theme.css("gruvbox")
    assert_includes css, "--accent"
    assert_includes css, "html.dark"
  end

  def test_unknown_theme_falls_back_to_default
    assert_equal Neuz::Theme.css("default"), Neuz::Theme.css("no-such-theme")
  end

  def test_invalid_name_falls_back_to_default
    assert_equal Neuz::Theme.css("default"), Neuz::Theme.css("../default")
  end

  def test_custom_dir_overrides_builtin
    FileUtils.mkdir_p(Neuz::Config.custom_themes_dir)
    File.write(
      File.join(Neuz::Config.custom_themes_dir, "default.css"),
      ":root{--accent:1 2 3}\nhtml.dark{--accent:4 5 6}\n",
    )
    Neuz::Theme.reset_cache!
    assert_includes Neuz::Theme.css("default"), "--accent:1 2 3"
  end

  def test_active_css_follows_config_theme
    old = ENV["NEUZ_THEME"]
    ENV["NEUZ_THEME"] = "tokyo-night"
    Neuz::Theme.reset_cache!
    assert_equal Neuz::Theme.css("tokyo-night"), Neuz::Theme.active_css
  ensure
    old.nil? ? ENV.delete("NEUZ_THEME") : ENV["NEUZ_THEME"] = old
    Neuz::Theme.reset_cache!
  end
end

class ThemeRouteTest < Minitest::Test
  include Neuz::TestSupport

  def test_theme_css_is_served
    get "/theme.css"
    assert_equal 200, last_response.status
    assert_includes last_response.headers["Content-Type"], "text/css"
    assert_includes last_response.body, "--accent"
    assert_includes last_response.body, "html.dark"
  end
end

require_relative "test_helper"

class ViewsTest < Minitest::Test
  include Neuz::TestSupport

  def test_empty_index_renders_empty_state
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You're all caught up."
    assert_includes last_response.body, "Enjoy the calm."
    assert_includes last_response.body, "Today"
  end

  def test_index_shows_an_item_for_today
    Neuz::DB.connection[:items].insert(
      external_id: "today-1",
      source_url: "https://example.com/today",
      published_at: Time.now.utc - 60,
      title: "Hello today",
      summary: "Summary",
      category: "ai",
      user_id: 1,
      created_at: Time.now.utc,
      updated_at: Time.now.utc,
    )
    get "/"
    assert_includes last_response.body, "Hello today"
    assert_includes last_response.body, "example.com"
  end

  def test_index_shows_items_ingested_today_even_if_source_is_old
    # An article the source published 4 days ago but Claude curated TODAY
    # should show up on today's dashboard.
    Neuz::DB.connection[:items].insert(
      external_id: "old-article",
      source_url: "https://example.com/old-but-relevant",
      published_at: Time.now.utc - 4 * 86_400,
      title: "Old source, fresh on dashboard",
      summary: "Curator picked this up today.",
      user_id: 1,
      created_at: Time.now.utc - 60,   # arrived 1min ago
      updated_at: Time.now.utc - 60,
    )
    get "/"
    assert_includes last_response.body, "Old source, fresh on dashboard"
  end

  def test_index_hides_items_ingested_yesterday_even_if_source_is_today
    # Inverse: a "live" article that arrived yesterday belongs to
    # yesterday's bucket, not today's.
    Neuz::DB.connection[:items].insert(
      external_id: "yesterday-arrival",
      source_url: "https://example.com/published-today",
      published_at: Time.now.utc,            # source published just now
      title: "Stale arrival",
      summary: "Arrived yesterday.",
      user_id: 1,
      created_at: Time.now.utc - 2 * 86_400,  # arrived 2 days ago
      updated_at: Time.now.utc - 2 * 86_400,
    )
    get "/"
    refute_includes last_response.body, "Stale arrival"
  end

  def test_day_route_404_on_bad_date
    get "/day/abc"
    assert_equal 404, last_response.status
  end

  def test_day_route_renders_for_valid_date
    # Day route buckets by created_at, so the row must have arrived on
    # the target day for the rendering to include it.
    iso = "2026-05-22"
    Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/day-test",
      published_at: Time.parse("#{iso}T12:00:00Z"),
      title: "Day item",
      summary: "Summary",
      user_id: 1,
      created_at: Time.parse("#{iso}T12:00:00Z"),
      updated_at: Time.parse("#{iso}T12:00:00Z"),
    )
    get "/day/#{iso}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Day item"
  end

  def test_month_route_404_on_bad_ym
    get "/month/2026-99"
    assert_equal 404, last_response.status
  end

  def test_month_route_renders_grid
    get "/month/2026-05"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "May 2026"
    assert_includes last_response.body, "role=\"grid\""
  end

  def test_brand_defaults_to_neuz_when_env_unset
    ENV.delete("NEUZ_BRAND")
    assert_equal "Neuz", Neuz::Config.brand
    get "/"
    assert_includes last_response.body, "<title>Neuz</title>"
    assert_includes last_response.body, ">Neuz</span>"
  end

  def test_brand_falls_back_for_empty_or_whitespace
    %w[  ].each do |val|
      ENV["NEUZ_BRAND"] = val
      assert_equal "Neuz", Neuz::Config.brand, "should fall back for #{val.inspect}"
    end
    ENV["NEUZ_BRAND"] = ""
    assert_equal "Neuz", Neuz::Config.brand
  ensure
    ENV.delete("NEUZ_BRAND")
  end

  def test_brand_uses_custom_value_when_set
    ENV["NEUZ_BRAND"] = "The Daily Pulse"
    ENV["NEUZ_TAGLINE"] = "morning brief"
    get "/"
    assert_includes last_response.body, "<title>The Daily Pulse</title>"
    assert_includes last_response.body, ">The Daily Pulse</span>"
    assert_includes last_response.body, "morning brief"
  ensure
    ENV.delete("NEUZ_BRAND")
    ENV.delete("NEUZ_TAGLINE")
  end

  def test_footer_links_to_upstream_github_by_default
    ENV.delete("NEUZ_REPO_URL")
    get "/"
    assert_includes last_response.body, %(href="https://github.com/vshvedov/neuz")
    assert_includes last_response.body, %(rel="noopener noreferrer")
    assert_includes last_response.body, %(aria-label="Source on GitHub")
  end

  def test_footer_repo_url_is_overridable
    ENV["NEUZ_REPO_URL"] = "https://example.com/my-fork"
    get "/"
    assert_includes last_response.body, %(href="https://example.com/my-fork")
    refute_includes last_response.body, %(href="https://github.com/vshvedov/neuz")
  ensure
    ENV.delete("NEUZ_REPO_URL")
  end

  def test_csp_header_present
    get "/"
    csp = last_response.headers["Content-Security-Policy"]
    refute_nil csp
    assert_includes csp, "default-src 'self'"
    assert_includes csp, "nonce-"
  end
end

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

  def test_day_route_404_on_bad_date
    get "/day/abc"
    assert_equal 404, last_response.status
  end

  def test_day_route_renders_for_valid_date
    iso = "2026-05-22"
    Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/day-test",
      published_at: Time.parse("#{iso}T12:00:00Z"),
      title: "Day item",
      summary: "Summary",
      user_id: 1,
      created_at: Time.now.utc,
      updated_at: Time.now.utc,
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

  def test_csp_header_present
    get "/"
    csp = last_response.headers["Content-Security-Policy"]
    refute_nil csp
    assert_includes csp, "default-src 'self'"
    assert_includes csp, "nonce-"
  end
end

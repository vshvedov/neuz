require_relative "test_helper"

class IngestTest < Minitest::Test
  include Neuz::TestSupport

  ITEM = {
    title: "Anthropic releases Claude 4.7",
    summary: "Claude 4.7 is the new flagship.",
    source_url: "https://example.com/claude-4-7",
    published_at: "2026-05-22T10:00:00Z",
    category: "AI",
    tags: ["claude", "models"],
    body: "## Key points\n\n- Faster\n- Smarter",
    importance: 5,
    external_id: "claude-4-7"
  }.freeze

  def test_happy_path_insert
    post_json "/api/items", { items: [ITEM] }, bearer(first_boot_key)
    assert_equal 200, last_response.status
    body = json_response
    assert_equal 1, body["accepted"]
    assert_equal 1, body["total"]
    assert_empty body["errors"]
    assert_equal 1, Neuz::DB.connection[:items].count
    item = Neuz::DB.connection[:items].first
    assert_equal "ai", item[:category] # lowercased
    tags = Neuz::DB.connection[:item_tags].where(item_id: item[:id]).select_map(:tag).sort
    assert_equal %w[claude models], tags
  end

  def test_invalid_batch_root
    post_json "/api/items", { not_items: "nope" }, bearer(first_boot_key)
    assert_equal 400, last_response.status
    assert_equal "invalid_batch", json_response["error"]
  end

  def test_partial_errors_returned
    bad = { title: "", summary: "x", source_url: "not-a-url", published_at: "yesterday" }
    post_json "/api/items", { items: [ITEM, bad] }, bearer(first_boot_key)
    assert_equal 200, last_response.status
    body = json_response
    assert_equal 1, body["accepted"]
    assert body["errors"].length >= 2
    assert_equal 1, body["errors"].find { |e| e["field"] == "title" }["index"]
  end

  def test_batch_size_limit
    items = Array.new(Neuz::Config.batch_limit + 1) do |i|
      ITEM.merge(external_id: "x#{i}", source_url: "https://example.com/#{i}")
    end
    post_json "/api/items", { items: items }, bearer(first_boot_key)
    assert_equal 413, last_response.status
    assert_equal "batch_too_large", json_response["error"]
  end

  def test_long_title_validation
    item = ITEM.merge(title: "x" * 600)
    post_json "/api/items", { items: [item] }, bearer(first_boot_key)
    assert_equal 200, last_response.status
    assert_equal 0, json_response["accepted"]
    err = json_response["errors"].first
    assert_equal "title", err["field"]
    assert_equal "too_long", err["code"]
  end

  def test_invalid_url_validation
    item = ITEM.merge(source_url: "ftp://nope.com")
    post_json "/api/items", { items: [item] }, bearer(first_boot_key)
    body = json_response
    assert_equal 0, body["accepted"]
    err = body["errors"].first
    assert_equal "source_url", err["field"]
  end
end

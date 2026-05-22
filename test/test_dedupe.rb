require_relative "test_helper"

class DedupeTest < Minitest::Test
  include Neuz::TestSupport

  def base
    {
      title: "Hello",
      summary: "Summary",
      source_url: "https://example.com/article",
      published_at: "2026-05-22T10:00:00Z",
      external_id: "ext-1",
      tags: ["a"]
    }
  end

  def test_dedupe_by_external_id_unchanged
    post_json "/api/items", { items: [base] }, bearer(first_boot_key)
    assert_equal 1, json_response["accepted"]
    post_json "/api/items", { items: [base] }, bearer(first_boot_key)
    body = json_response
    assert_equal 0, body["accepted"]
    assert_equal 1, body["deduped"]
    assert_equal 0, body["updated"]
    assert_equal 1, Neuz::DB.connection[:items].count
  end

  def test_dedupe_by_external_id_update_on_change
    post_json "/api/items", { items: [base] }, bearer(first_boot_key)
    updated = base.merge(title: "Hello, again")
    post_json "/api/items", { items: [updated] }, bearer(first_boot_key)
    body = json_response
    assert_equal 1, body["updated"]
    assert_equal 0, body["accepted"]
    assert_equal "Hello, again", Neuz::DB.connection[:items].first[:title]
  end

  def test_dedupe_by_source_url_alone
    # No external_id and *different* published_at on the second push:
    # under the old (source_url, date) key this would create a 2nd row.
    # Under the URL-only key, it must collapse into one upsert.
    no_id = base.dup
    no_id.delete(:external_id)

    post_json "/api/items", { items: [no_id] }, bearer(first_boot_key)
    assert_equal 1, json_response["accepted"]

    same_url_different_day = no_id.merge(
      published_at: "2026-05-29T10:00:00Z",
      title: "Hello (updated)",
    )
    post_json "/api/items", { items: [same_url_different_day] }, bearer(first_boot_key)
    body = json_response
    assert_equal 0, body["accepted"]
    assert_equal 1, body["deduped"] + body["updated"]
    assert_equal 1, Neuz::DB.connection[:items].count
    assert_equal "Hello (updated)", Neuz::DB.connection[:items].first[:title]
  end

  def test_tag_reconciliation_on_update
    post_json "/api/items", { items: [base] }, bearer(first_boot_key)
    changed = base.merge(tags: ["b", "c"])
    post_json "/api/items", { items: [changed] }, bearer(first_boot_key)
    assert_equal 1, json_response["updated"]
    item_id = Neuz::DB.connection[:items].first[:id]
    tags = Neuz::DB.connection[:item_tags].where(item_id: item_id).select_map(:tag).sort
    assert_equal %w[b c], tags
  end
end

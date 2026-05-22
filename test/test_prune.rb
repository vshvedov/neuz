require_relative "test_helper"

class PruneTest < Minitest::Test
  include Neuz::TestSupport

  def test_prune_removes_items_past_cutoff
    old_time = Time.now.utc - 100 * 86_400
    new_time = Time.now.utc - 10 * 86_400
    Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/old",
      published_at: old_time,
      title: "Old",
      summary: "Old",
      user_id: 1,
      created_at: old_time,
      updated_at: old_time,
    )
    Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/new",
      published_at: new_time,
      title: "New",
      summary: "New",
      user_id: 1,
      created_at: new_time,
      updated_at: new_time,
    )
    deleted = Neuz::Prune.run!(90)
    assert_equal 1, deleted
    titles = Neuz::DB.connection[:items].select_map(:title)
    assert_equal ["New"], titles
  end

  def test_prune_zero_days_disables
    Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/x",
      published_at: Time.now.utc - 365 * 86_400,
      title: "Old",
      summary: "Old",
      user_id: 1,
      created_at: Time.now.utc,
      updated_at: Time.now.utc,
    )
    assert_equal 0, Neuz::Prune.run!(0)
    assert_equal 1, Neuz::DB.connection[:items].count
  end

  def test_prune_removes_tags_too
    old = Time.now.utc - 200 * 86_400
    id = Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/o",
      published_at: old,
      title: "Old",
      summary: "Old",
      user_id: 1,
      created_at: old,
      updated_at: old,
    )
    Neuz::DB.connection[:item_tags].insert(item_id: id, tag: "x")
    Neuz::Prune.run!(30)
    assert_equal 0, Neuz::DB.connection[:item_tags].where(item_id: id).count
  end
end

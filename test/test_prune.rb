require_relative "test_helper"

class PruneTest < Minitest::Test
  include Neuz::TestSupport

  def test_prune_removes_items_past_cutoff
    # Prune now keys on created_at (arrival time), not published_at.
    old_arrival = Time.now.utc - 100 * 86_400
    new_arrival = Time.now.utc - 10 * 86_400
    Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/old",
      published_at: old_arrival,
      title: "Old",
      summary: "Old",
      user_id: 1,
      created_at: old_arrival,
      updated_at: old_arrival,
    )
    Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/new",
      published_at: new_arrival,
      title: "New",
      summary: "New",
      user_id: 1,
      created_at: new_arrival,
      updated_at: new_arrival,
    )
    deleted = Neuz::Prune.run!(90)
    assert_equal 1, deleted
    titles = Neuz::DB.connection[:items].select_map(:title)
    assert_equal ["New"], titles
  end

  def test_prune_keeps_recently_arrived_old_source_articles
    # The classic case: source published 100 days ago, but Claude
    # surfaced it for us today. Must NOT be pruned.
    old_pub = Time.now.utc - 100 * 86_400
    Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/old-source-fresh-arrival",
      published_at: old_pub,
      title: "Old source, fresh today",
      summary: "Curator picked this up today.",
      user_id: 1,
      created_at: Time.now.utc - 60,  # arrived a minute ago
      updated_at: Time.now.utc - 60,
    )
    assert_equal 0, Neuz::Prune.run!(90)
    assert_equal 1, Neuz::DB.connection[:items].count
  end

  def test_prune_zero_days_disables
    Neuz::DB.connection[:items].insert(
      source_url: "https://example.com/x",
      published_at: Time.now.utc - 365 * 86_400,
      title: "Old",
      summary: "Old",
      user_id: 1,
      created_at: Time.now.utc - 365 * 86_400,
      updated_at: Time.now.utc - 365 * 86_400,
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

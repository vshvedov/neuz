require_relative "test_helper"

class ValidationTest < Minitest::Test
  include Neuz::TestSupport

  def test_validator_accepts_minimal_item
    item = {
      "title" => "Hi",
      "summary" => "Sum",
      "source_url" => "https://x.com/a",
      "published_at" => "2026-05-22T10:00:00Z",
    }
    normalized, errors = Neuz::Validators.validate_item(item)
    assert_empty errors
    assert_kind_of Time, normalized["published_at"]
  end

  def test_validator_rejects_missing_required
    normalized, errors = Neuz::Validators.validate_item({})
    assert_nil normalized
    fields = errors.map { |e| e[:field] }.sort
    assert_equal Neuz::Validators::REQUIRED.sort, fields & Neuz::Validators::REQUIRED
  end

  def test_validator_rejects_importance_out_of_range
    item = {
      "title" => "Hi",
      "summary" => "Sum",
      "source_url" => "https://x.com/a",
      "published_at" => "2026-05-22T10:00:00Z",
      "importance" => 9,
    }
    _, errors = Neuz::Validators.validate_item(item)
    assert errors.any? { |e| e[:field] == "importance" && e[:code] == "out_of_range" }
  end

  def test_validator_normalizes_category_lowercase
    item = {
      "title" => "Hi",
      "summary" => "Sum",
      "source_url" => "https://x.com/a",
      "published_at" => "2026-05-22T10:00:00Z",
      "category" => "AI",
    }
    normalized, _ = Neuz::Validators.validate_item(item)
    assert_equal "ai", normalized["category"]
  end

  def test_validator_caps_tags
    item = {
      "title" => "Hi",
      "summary" => "Sum",
      "source_url" => "https://x.com/a",
      "published_at" => "2026-05-22T10:00:00Z",
      "tags" => Array.new(30) { |i| "t#{i}" },
    }
    normalized, _ = Neuz::Validators.validate_item(item)
    assert_equal 20, normalized["tags"].length
  end

  def test_validator_rejects_bad_url
    item = {
      "title" => "Hi",
      "summary" => "Sum",
      "source_url" => "javascript:alert(1)",
      "published_at" => "2026-05-22T10:00:00Z",
    }
    _, errors = Neuz::Validators.validate_item(item)
    assert errors.any? { |e| e[:field] == "source_url" }
  end
end

require_relative "test_helper"

class RateLimitTest < Minitest::Test
  include Neuz::TestSupport

  def setup
    ENV["NEUZ_RATE_CAPACITY"] = "3"
    ENV["NEUZ_RATE_REFILL_PER_MIN"] = "6" # 0.1/sec
    super
  end

  def teardown
    ENV.delete("NEUZ_RATE_CAPACITY")
    ENV.delete("NEUZ_RATE_REFILL_PER_MIN")
    super
  end

  def test_exhausts_and_returns_429
    key = first_boot_key
    3.times do |i|
      post_json "/api/items", { items: [] }, bearer(key)
      assert_equal 200, last_response.status, "request #{i} should still be allowed"
    end
    post_json "/api/items", { items: [] }, bearer(key)
    assert_equal 429, last_response.status
    body = json_response
    assert_equal "rate_limited", body["error"]
    assert body["retry_after_seconds"].to_i >= 1
    assert_equal body["retry_after_seconds"].to_s, last_response.headers["Retry-After"]
  end
end

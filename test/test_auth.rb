require_relative "test_helper"

class AuthTest < Minitest::Test
  include Neuz::TestSupport

  def test_ingest_rejects_missing_auth
    post_json "/api/items", { items: [] }
    assert_equal 401, last_response.status
    assert_equal "unauthorized", json_response["error"]
  end

  def test_ingest_rejects_wrong_auth
    post_json "/api/items", { items: [] }, bearer("nope")
    assert_equal 401, last_response.status
  end

  def test_ingest_accepts_correct_auth_with_empty_batch
    post_json "/api/items", { items: [] }, bearer(first_boot_key)
    assert_equal 200, last_response.status
    body = json_response
    assert_equal 0, body["accepted"]
    assert_equal 0, body["total"]
  end

  def test_ingest_rejects_non_bearer_scheme
    post_json "/api/items", { items: [] },
      "HTTP_AUTHORIZATION" => "Basic #{first_boot_key}"
    assert_equal 401, last_response.status
  end
end

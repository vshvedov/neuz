require_relative "test_helper"

class HealthzTest < Minitest::Test
  include Neuz::TestSupport

  def test_healthz_returns_ok_json
    get "/healthz"
    assert_equal 200, last_response.status
    body = json_response
    assert_equal "ok", body["status"]
    assert_equal "ok", body["db"]
    assert_kind_of Integer, body["items_total"]
    assert_kind_of Integer, body["items_today"]
    assert_match(/\A\d+\.\d+\.\d+\z/, body["version"])
  end

  def test_healthz_no_auth_required
    get "/healthz"
    assert_equal 200, last_response.status
  end
end

require "digest"
require "rack/utils"

module Neuz
  module Auth
    module_function

    def digest(raw)
      Digest::SHA256.hexdigest(raw.to_s)
    end

    # Bearer token from the Authorization header, raw key returned as a
    # string or nil if absent/malformed.
    def extract_bearer(env)
      header = env["HTTP_AUTHORIZATION"] || env["Authorization"]
      return nil unless header

      scheme, value = header.to_s.split(" ", 2)
      return nil unless scheme && scheme.downcase == "bearer"
      return nil if value.nil? || value.empty?

      value.strip
    end

    # Constant-time verify of presented bearer against any active api_keys row.
    # Returns the api_keys row (Hash) on success, nil on failure.
    def verify(env)
      presented = extract_bearer(env)
      return nil unless presented

      presented_digest = digest(presented)
      DB.connection[:api_keys].all.each do |row|
        stored = row[:sha256].to_s
        next if stored.length != presented_digest.length

        return row if Rack::Utils.secure_compare(presented_digest, stored)
      end
      nil
    end

    def touch_last_used!(api_key_id)
      DB.connection[:api_keys].where(id: api_key_id).update(last_used_at: Time.now.utc)
    end
  end
end

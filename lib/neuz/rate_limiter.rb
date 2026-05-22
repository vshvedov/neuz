module Neuz
  module RateLimiter
    module_function

    # Token-bucket consume. Returns :ok or { retry_after: seconds }.
    # Atomic under SQLite: we run inside a transaction and use the bucket
    # row as a lock via UPDATE. SQLite serializes writes anyway.
    def consume(api_key_id, capacity: Config.rate_capacity, refill_per_sec: Config.rate_refill_per_sec)
      DB.connection.transaction do
        now = Time.now.utc
        bucket = DB.connection[:rate_buckets].where(api_key_id: api_key_id).for_update.first
        bucket ||= begin
          DB.connection[:rate_buckets].insert(
            api_key_id: api_key_id,
            tokens: capacity.to_f,
            refilled_at: now,
          )
          { api_key_id: api_key_id, tokens: capacity.to_f, refilled_at: now }
        end

        elapsed = now - to_time(bucket[:refilled_at])
        elapsed = 0.0 if elapsed.negative?
        tokens = [bucket[:tokens].to_f + elapsed * refill_per_sec, capacity.to_f].min

        if tokens >= 1.0
          tokens -= 1.0
          DB.connection[:rate_buckets].where(api_key_id: api_key_id).update(
            tokens: tokens,
            refilled_at: now,
          )
          :ok
        else
          deficit = 1.0 - tokens
          retry_after = (deficit / refill_per_sec).ceil
          DB.connection[:rate_buckets].where(api_key_id: api_key_id).update(
            tokens: tokens,
            refilled_at: now,
          )
          { retry_after: [retry_after, 1].max }
        end
      end
    end

    def to_time(value)
      return value if value.is_a?(Time)
      Time.parse(value.to_s).utc
    end
  end
end

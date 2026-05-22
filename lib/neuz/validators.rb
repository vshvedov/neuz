require "time"
require "uri"

module Neuz
  module Validators
    module_function

    REQUIRED = %w[title summary source_url published_at].freeze
    MAX_LEN = {
      "title" => 500,
      "summary" => 2000,
      "body" => 50_000,
      "category" => 50,
      "external_id" => 200,
      "image_url" => 2000,
      "source_url" => 2000,
    }.freeze

    # Validate a single item hash. Returns [normalized_hash, errors].
    # errors is an array of {field:, code:, message:}.
    def validate_item(raw)
      errors = []
      out = {}

      return [nil, [{ field: "_root", code: "invalid_type", message: "item must be an object" }]] unless raw.is_a?(Hash)

      raw = raw.transform_keys(&:to_s)

      REQUIRED.each do |key|
        if raw[key].nil? || (raw[key].is_a?(String) && raw[key].strip.empty?)
          errors << { field: key, code: "missing", message: "#{key} is required" }
        end
      end

      %w[title summary source_url category external_id image_url body].each do |key|
        value = raw[key]
        next if value.nil?

        unless value.is_a?(String)
          errors << { field: key, code: "invalid_type", message: "#{key} must be a string" }
          next
        end

        limit = MAX_LEN[key]
        if limit && value.length > limit
          errors << { field: key, code: "too_long", message: "#{key} exceeds #{limit} characters" }
        end

        out[key] = value.strip if value.is_a?(String)
      end

      %w[source_url image_url].each do |key|
        value = out[key]
        next if value.nil? || value.empty?

        begin
          uri = URI.parse(value)
          unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
            errors << { field: key, code: "invalid_format", message: "#{key} must be a http(s) URL" }
          end
        rescue URI::InvalidURIError
          errors << { field: key, code: "invalid_format", message: "#{key} is not a valid URL" }
        end
      end

      if raw["published_at"]
        begin
          out["published_at"] = Time.parse(raw["published_at"].to_s).utc
        rescue ArgumentError, TypeError
          errors << { field: "published_at", code: "invalid_format", message: "published_at must be ISO8601" }
        end
      end

      if raw.key?("importance")
        value = raw["importance"]
        if value.is_a?(Integer) && (1..5).cover?(value)
          out["importance"] = value
        else
          errors << { field: "importance", code: "out_of_range", message: "importance must be 1..5" }
        end
      end

      if raw.key?("tags")
        tags = raw["tags"]
        if tags.is_a?(Array) && tags.all? { |t| t.is_a?(String) }
          out["tags"] = tags.map(&:strip).reject(&:empty?).uniq.first(20)
        else
          errors << { field: "tags", code: "invalid_type", message: "tags must be an array of strings" }
        end
      end

      out["category"] = out["category"].downcase if out["category"]

      [errors.empty? ? out : nil, errors]
    end
  end
end

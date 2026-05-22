module Neuz
  module Ingest
    module_function

    MUTABLE_FIELDS = %w[title summary body image_url importance category].freeze

    # Process a batch of items. Returns {accepted, updated, deduped, errors, total}.
    def batch(items, api_key_id)
      result = { accepted: 0, updated: 0, deduped: 0, errors: [], total: items.length }

      items.each_with_index do |raw, index|
        normalized, errors = Validators.validate_item(raw)
        if errors.any?
          errors.each { |e| result[:errors] << e.merge(index: index) }
          next
        end

        outcome = upsert(normalized, raw["external_id"] || raw[:external_id])
        result[:accepted] += 1 if outcome == :inserted
        result[:updated] += 1 if outcome == :updated
        result[:deduped] += 1 if outcome == :unchanged
      end

      Auth.touch_last_used!(api_key_id) if result[:accepted].positive? || result[:updated].positive?
      result
    end

    def upsert(item, external_id)
      DB.connection.transaction do
        existing = find_existing(item, external_id)
        if existing
          changes = MUTABLE_FIELDS.each_with_object({}) do |field, acc|
            new_value = item[field]
            acc[field.to_sym] = new_value if new_value != existing[field.to_sym]
          end

          tags_changed = tags_diff?(existing[:id], item["tags"])
          if changes.empty? && !tags_changed
            :unchanged
          else
            changes[:updated_at] = Time.now.utc
            DB.connection[:items].where(id: existing[:id]).update(changes) unless changes.empty?
            sync_tags(existing[:id], item["tags"]) if tags_changed
            :updated
          end
        else
          insert_new(item, external_id)
          :inserted
        end
      end
    rescue Sequel::UniqueConstraintViolation
      # Race condition with another worker. Retry once by treating as dedupe.
      :unchanged
    end

    def find_existing(item, external_id)
      ds = DB.connection[:items]
      if external_id && !external_id.to_s.strip.empty?
        row = ds.where(external_id: external_id.to_s).first
        return row if row
      end
      # source_url alone is the canonical dedupe key. Reposting the same
      # URL updates the existing row regardless of published_at — see
      # migration 006 and README "AI slop / selection drift" note.
      ds.where(source_url: item["source_url"]).first
    end

    def insert_new(item, external_id)
      now = Time.now.utc
      row_id = DB.connection[:items].insert(
        external_id: external_id&.to_s,
        source_url: item["source_url"],
        published_at: item["published_at"],
        title: item["title"],
        summary: item["summary"],
        body: item["body"],
        image_url: item["image_url"],
        importance: item["importance"],
        category: item["category"],
        user_id: 1,
        created_at: now,
        updated_at: now,
      )
      sync_tags(row_id, item["tags"]) if item["tags"]&.any?
      row_id
    end

    def sync_tags(item_id, tags)
      DB.connection[:item_tags].where(item_id: item_id).delete
      return if tags.nil? || tags.empty?

      DB.connection[:item_tags].multi_insert(
        tags.map { |t| { item_id: item_id, tag: t } },
      )
    end

    def tags_diff?(item_id, new_tags)
      existing = DB.connection[:item_tags].where(item_id: item_id).select_map(:tag).sort
      Array(new_tags).sort != existing
    end
  end
end

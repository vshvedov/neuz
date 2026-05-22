module Neuz
  module Prune
    module_function

    def start!
      return if @thread&.alive?

      interval = Config.prune_interval_seconds
      days = Config.prune_days
      return if days.zero?

      @thread = Thread.new do
        loop do
          sleep interval
          begin
            run!(days)
          rescue StandardError => e
            warn "[neuz.prune] #{e.class}: #{e.message}"
          end
        end
      end
      @thread.name = "neuz-prune" if @thread.respond_to?(:name=)
      @thread
    end

    def run!(days = Config.prune_days)
      return 0 if days.zero?

      # Prune by arrival time (created_at), not source publish date. This
      # matches how the index/calendar bucket items, and prevents the
      # corner case where a fresh ingest of an old article would be
      # pruned the moment it arrives.
      cutoff = Time.now.utc - (days * 86_400)
      DB.connection.transaction do
        ids = DB.connection[:items].where(Sequel.lit("created_at < ?", cutoff)).select_map(:id)
        next 0 if ids.empty?

        DB.connection[:item_tags].where(item_id: ids).delete
        DB.connection[:items].where(id: ids).delete
        ids.length
      end
    end
  end
end

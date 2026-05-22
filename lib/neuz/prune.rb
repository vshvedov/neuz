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

      cutoff = Time.now.utc - (days * 86_400)
      DB.connection.transaction do
        ids = DB.connection[:items].where(Sequel.lit("published_at < ?", cutoff)).select_map(:id)
        next 0 if ids.empty?

        DB.connection[:item_tags].where(item_id: ids).delete
        DB.connection[:items].where(id: ids).delete
        ids.length
      end
    end
  end
end

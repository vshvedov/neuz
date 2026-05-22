Sequel.migration do
  up do
    # Drop the (source_url, date(published_at)) unique index — we now
    # treat source_url as the dedupe key on its own. Re-posting the same
    # URL updates the existing row regardless of published_at.
    run "DROP INDEX IF EXISTS items_source_url_day_idx"

    # If any URL appears more than once (from before this migration), keep
    # the highest id (most recently inserted/updated) and delete the rest.
    # Tag rows cascade via FK.
    self[:items]
      .select_group(:source_url)
      .select_append { count(Sequel.lit("*")).as(:cnt) }
      .having { Sequel.lit("count(*) > 1") }
      .all
      .each do |row|
        keeper = self[:items].where(source_url: row[:source_url]).order(Sequel.desc(:id)).first[:id]
        self[:items].where(source_url: row[:source_url]).exclude(id: keeper).delete
      end

    add_index :items, :source_url, unique: true, name: :items_source_url_unique_idx
  end

  down do
    run "DROP INDEX IF EXISTS items_source_url_unique_idx"
    run "CREATE UNIQUE INDEX IF NOT EXISTS items_source_url_day_idx ON items(source_url, date(published_at))"
  end
end

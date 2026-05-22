Sequel.migration do
  change do
    create_table(:items) do
      primary_key :id
      Integer :user_id, null: false, default: 1
      String :external_id
      String :source_url, null: false
      DateTime :published_at, null: false
      String :title, null: false
      String :summary, null: false
      String :body
      String :image_url
      Integer :importance
      String :category
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :published_at
      index :category
      index :user_id
      index :external_id, unique: true, where: Sequel.lit("external_id IS NOT NULL")
    end

    run "CREATE UNIQUE INDEX IF NOT EXISTS items_source_url_day_idx ON items(source_url, date(published_at))"
  end
end

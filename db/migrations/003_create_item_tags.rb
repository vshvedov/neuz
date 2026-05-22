Sequel.migration do
  change do
    create_table(:item_tags) do
      foreign_key :item_id, :items, null: false, on_delete: :cascade
      String :tag, null: false

      primary_key %i[item_id tag]
      index %i[tag item_id]
    end
  end
end

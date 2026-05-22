Sequel.migration do
  change do
    create_table(:api_keys) do
      primary_key :id
      Integer :user_id, null: false, default: 1
      String :sha256, null: false, fixed: false
      String :label, null: false, default: "default"
      DateTime :created_at, null: false
      DateTime :last_used_at

      index :sha256, unique: true
      index :user_id
    end
  end
end

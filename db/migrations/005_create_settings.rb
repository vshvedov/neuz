Sequel.migration do
  change do
    create_table(:settings) do
      String :key, primary_key: true
      String :value
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end

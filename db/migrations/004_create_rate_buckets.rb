Sequel.migration do
  change do
    create_table(:rate_buckets) do
      foreign_key :api_key_id, :api_keys, primary_key: true, on_delete: :cascade
      Float :tokens, null: false, default: 0.0
      DateTime :refilled_at, null: false
    end
  end
end

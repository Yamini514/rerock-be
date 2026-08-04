Sequel.migration do
  change do
    create_table(:amenities) do
      primary_key :id
      String :slug, null: false
      String :name, null: false
      String :icon, default: 'Sparkles'
      String :category, null: false
      Boolean :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :category
    end
  end
end

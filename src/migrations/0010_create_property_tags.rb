Sequel.migration do
  change do
    create_table(:property_tags) do
      primary_key :id
      String :slug, null: false
      String :name, null: false
      String :colour, null: false, default: '#B3421C'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
    end
  end
end

Sequel.migration do
  change do
    create_table(:roles) do
      primary_key :id
      String :slug, null: false
      String :name, null: false
      Integer :level, default: 10
      Boolean :is_super_admin, default: false
      String :status, default: 'Active'
      String :description, text: true
      column :permissions, 'text[]', default: '{}'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
    end
  end
end

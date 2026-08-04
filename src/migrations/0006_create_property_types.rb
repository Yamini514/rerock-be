Sequel.migration do
  change do
    create_table(:property_types) do
      primary_key :id
      String :slug, null: false
      String :name, null: false
      String :description, text: true
      String :icon, default: 'Building2'
      String :banner
      String :image
      Integer :display_order, default: 0
      String :colour, default: '#B3421C'
      Boolean :active, default: true
      Boolean :show_on_homepage, default: false
      Boolean :allow_search, default: true
      column :seo, :jsonb, default: '{"title":"","description":""}'
      Boolean :archived, default: false

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :archived
      index :display_order
    end
  end
end

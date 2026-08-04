Sequel.migration do
  change do
    create_table(:areas) do
      primary_key :id
      String :slug, null: false
      String :name, null: false
      String :city, default: 'Hyderabad'
      String :state, default: 'Telangana'
      String :country, default: 'India'
      String :image
      Integer :avg_price_per_sqft, default: 0
      Float :growth_pct, default: 0
      Float :lat
      Float :lng
      String :description, text: true
      Integer :display_order, default: 0
      Boolean :active, default: true
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

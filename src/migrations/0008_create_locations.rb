Sequel.migration do
  change do
    create_table(:locations) do
      primary_key :id
      String :slug, null: false
      String :name, null: false
      foreign_key :area_id, :areas, null: false
      String :city
      String :pincode
      Float :lat
      Float :lng
      Boolean :metro, default: false
      Boolean :bus, default: false
      column :nearby_landmarks, 'text[]', default: '{}'
      column :schools, 'text[]', default: '{}'
      column :hospitals, 'text[]', default: '{}'
      Integer :airport_distance_km, default: 0
      Integer :display_order, default: 0
      String :status, default: 'Active'
      column :seo, :jsonb, default: '{"title":"","description":""}'
      Boolean :archived, default: false

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :area_id
      index :archived
      index :display_order
    end
  end
end

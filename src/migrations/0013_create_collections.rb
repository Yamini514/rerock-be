Sequel.migration do
  change do
    create_table(:collections) do
      primary_key :id
      String :slug, null: false
      String :name, null: false
      String :description, text: true
      String :cover_image
      # Curated membership: real property ids, not slugs — same zero-custom-code
      # plain Postgres integer[] precedent as Community#amenity_ids
      # (migrations/0011) and Property#tag_ids/#amenity_ids (migrations/0012),
      # rather than a collection_properties join table. Base#create/#update
      # just slice+assign via data_for(:save); db.extension :pg_array (already
      # enabled in app.rb) handles the typecast with zero custom code.
      column :property_ids, 'integer[]', default: '{}'
      Boolean :active, default: true
      Integer :display_order, default: 0

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :display_order
    end
  end
end

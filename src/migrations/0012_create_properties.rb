Sequel.migration do
  change do
    create_table(:properties) do
      primary_key :id
      String :slug, null: false
      String :title, null: false

      # Real FKs — Communities, Builders, Areas, Locations, and Property Types
      # are all built modules by the time Properties lands, so (unlike when
      # Communities was built and `type` had to stay a free-text string) every
      # one of these is a real integer FK now, matching the FK conventions
      # already established in migrations/0011_create_communities.rb.
      foreign_key :community_id, :communities, null: false
      foreign_key :builder_id, :builders, null: false
      foreign_key :area_id, :areas, null: false
      foreign_key :location_id, :locations, null: false
      foreign_key :property_type_id, :property_types, null: false

      String :status, default: 'Available'
      Integer :price, default: 0
      Integer :price_per_sqft, default: 0
      Integer :built_up_area
      Integer :land_area
      Date :created_date, default: Sequel::CURRENT_DATE

      Integer :bedrooms
      Integer :bathrooms
      Integer :balconies
      String :facing
      String :floor
      Boolean :rera, default: true

      column :images, 'text[]', default: '{}'
      column :highlights, 'text[]', default: '{}'
      String :description, text: true
      column :floor_plans, :jsonb, default: '[]'
      column :pricing_trend, :jsonb, default: '[]'

      # Agent Network isn't built yet — deferred FK per the established
      # "keep it a plain nullable string column until that module lands"
      # pattern (same reasoning documented for Builder/Community fields that
      # reference not-yet-built modules).
      String :agent_slug

      Boolean :featured, default: false

      # Property Tags and Amenities are both real, built modules — modeled as
      # plain Postgres integer[] columns (same as Community's `amenity_ids`
      # in migrations/0011), not join tables. See services/properties.rb and
      # ARCHITECTURE.md for the full reasoning (already established there).
      column :tag_ids, 'integer[]', default: '{}'
      column :amenity_ids, 'integer[]', default: '{}'

      Integer :investment_score
      String :advisor_notes, text: true
      # Agent Network isn't built yet, so the sales team stays a plain jsonb
      # array of agent slugs (no real FK target to point at yet), matching
      # `agent_slug` above.
      column :sales_team, :jsonb, default: '[]'

      String :publish_status, default: 'Draft'
      DateTime :publish_at
      column :seo, :jsonb, default: '{"slug":"","title":"","description":"","keywords":"","ogImage":null}'
      column :videos, 'text[]', default: '{}'
      String :tour_360
      String :virtual_tour
      column :documents, :jsonb, default: '[]'
      Boolean :archived, default: false

      # Extra fields already present on the existing (mock-backed) admin
      # PropertyForm/list/detail UI beyond lib/data/properties.js's own sample
      # records (code, configuration, unit number, offer/booking pricing,
      # maintenance, parking, furnishing, advantages, specifications) — kept
      # as real columns too so the existing form/detail UI keeps working
      # as-is rather than losing fields on rewire.
      String :code
      String :configuration
      String :unit_number
      Integer :offer_price
      Integer :booking_amount
      Integer :maintenance
      String :pricing_notes, text: true
      Integer :parking
      String :furnishing, default: 'Unfurnished'
      column :advantages, 'text[]', default: '{}'
      column :specifications, 'text[]', default: '{}'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :community_id
      index :builder_id
      index :area_id
      index :location_id
      index :property_type_id
      index :status
      index :featured
      index :archived
    end
  end
end

Sequel.migration do
  change do
    create_table(:communities) do
      primary_key :id
      String :slug, null: false
      String :name, null: false
      String :type
      foreign_key :builder_id, :builders, null: false
      foreign_key :area_id, :areas, null: false
      foreign_key :location_id, :locations, null: false
      String :tagline
      String :status, default: 'Under Construction'
      Boolean :featured, default: false
      Boolean :trending, default: false
      Boolean :homepage_visibility, default: true
      String :rera
      # priceRange {min,max} from the mock stored as two plain integer columns
      # rather than jsonb — this resource already sorts/filters on starting
      # price (the list page's "Starting Price" sortable column), which is a
      # lot simpler as `price_min`/`price_max` than reaching into a jsonb blob
      # for every query. See services/communities.rb and ARCHITECTURE.md for
      # the same reasoning written out.
      Integer :price_min, default: 0
      Integer :price_max, default: 0
      column :unit_types, 'text[]', default: '{}'
      Integer :total_units, default: 0
      Integer :available_units, default: 0
      String :possession
      Integer :investment_score, default: 0
      Float :growth_pct, default: 0
      Date :last_price_update
      String :hero_image
      column :gallery, 'text[]', default: '{}'
      String :overview, text: true
      String :master_plan, text: true
      # Many-to-many to amenities modeled as a plain Postgres integer[] of
      # amenity ids (matching Builder's awards/certifications text[] precedent)
      # rather than a community_amenities join table — see services/communities.rb
      # and ARCHITECTURE.md for the full reasoning.
      column :amenity_ids, 'integer[]', default: '{}'
      column :pricing_trend, :jsonb, default: '[]'
      column :nearby, :jsonb, default: '[]'
      column :documents, :jsonb, default: '[]'
      column :seo, :jsonb, default: '{"title":"","description":""}'
      Boolean :archived, default: false

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :builder_id
      index :area_id
      index :location_id
      index :status
      index :archived
    end
  end
end

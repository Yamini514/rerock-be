Sequel.migration do
  change do
    create_table(:seo_pages) do
      primary_key :id

      # Matches lib/data/seoPages.js's field catalog exactly: one row per
      # public-facing route, with a unique `route` (the mock's own comment
      # implies uniqueness — no two rows should describe the same path) and
      # a 0-100 `score` used by the admin list's KPI/attention columns.
      String :route, null: false
      String :meta_title, null: false
      String :meta_description, text: true
      Integer :score, default: 0

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :route, unique: true
    end
  end
end

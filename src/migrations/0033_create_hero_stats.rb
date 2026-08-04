Sequel.migration do
  change do
    create_table(:hero_stats) do
      primary_key :id

      # Matches lib/data/homeContent.js's heroStats[] field catalog exactly.
      # No slug/status/archived column — the mock's own string `id` (e.g.
      # "stat1") is purely an array key, not a display slug, same reasoning
      # as Testimonials'/FAQs' plain-array mocks.
      String :label, null: false
      Integer :value, null: false, default: 0
      String :suffix, default: ''

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end

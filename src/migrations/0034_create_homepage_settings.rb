Sequel.migration do
  change do
    # Singleton settings row for lib/data/homeContent.js's heroSocialProof —
    # a single {investorsLabel, ratingLabel} config object with no natural
    # "many rows" shape. Modeled as its own table with exactly one row
    # (lazily created on first read/write by services/homepage_settings.rb),
    # rather than a generic key/value settings table or extra columns bolted
    # onto hero_stats — see services/homepage_settings.rb for the full
    # reasoning. No `id` is ever passed by the frontend; the service always
    # resolves to the one existing row (or creates it).
    create_table(:homepage_settings) do
      primary_key :id

      String :investors_label, default: ''
      String :rating_label, default: ''

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end

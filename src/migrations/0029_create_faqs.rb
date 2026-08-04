Sequel.migration do
  change do
    create_table(:faqs) do
      primary_key :id

      # Freeform string per lib/data/faqs.js's `category` field (e.g. "Buying",
      # "Legal & RERA") — no separate categories table. The mock's
      # `faqCategories` is just `Array.from(new Set(faqs.map(f => f.category)))`,
      # so the frontend keeps doing the same distinct-values derivation over
      # the real fetched list instead of a second lookup table/endpoint.
      String :category, null: false
      String :q, text: true, null: false
      String :a, text: true, null: false

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :category
    end
  end
end

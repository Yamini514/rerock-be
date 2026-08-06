Sequel.migration do
  change do
    create_table(:saved_properties) do
      primary_key :id

      foreign_key :client_id, :clients, null: false
      foreign_key :property_id, :properties, null: false

      # "saved" (uncapped favorites/wishlist) vs "shortlist" (capped at 2,
      # side-by-side comparison — see services/client_saved_properties.rb's
      # SHORTLIST_LIMIT) — one table, distinguished by kind, rather than two
      # near-identical tables. Row existence = "this client has this
      # property in this list", no separate boolean, same convention as
      # notification_reads (migrations/0048).
      String :kind, null: false # "saved" | "shortlist"

      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index [:client_id, :property_id, :kind], unique: true
      index [:client_id, :kind]
    end
  end
end

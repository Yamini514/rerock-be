Sequel.migration do
  change do
    create_table(:recommendations) do
      primary_key :id

      foreign_key :client_id, :clients, null: false
      foreign_key :property_id, :properties, null: false

      # Denormalized display fields, populated at creation time from the
      # resolved Client/Property rows — same convention as Lead#client_name/
      # SiteVisit#client_name alongside their own FKs, so the RAM "My
      # Recommendations" table can render without every row needing a join.
      String :client_name
      String :client_phone
      String :property_slug
      String :property_title

      # RAM/Agent Network aren't real resources yet — same deferred-FK-by-
      # slug convention already used for Property#agent_slug/Lead#agent_slug/
      # SiteVisit#agent_slug/Client#assigned_ram_id. sender_type distinguishes
      # which portal's identity table sender_slug points into.
      String :sender_type, null: false # "ram" | "agent"
      String :sender_slug, null: false

      String :remarks, text: true
      Integer :expected_budget
      # Mirrors lib/data/recommendations.js's own priority/status lists
      # exactly (RAM Portal's real "My Recommendations" page already renders
      # these) — plain strings with an app-level allowed list, same
      # convention as every other status column in this codebase.
      String :priority, default: 'Medium' # High | Medium | Low
      String :status, default: 'Sent' # Sent | Viewed | Interested | Site Visit | Negotiation | Booked | Rejected

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :client_id
      index :property_id
      index :sender_slug
      index :status
    end
  end
end

Sequel.migration do
  change do
    create_table(:site_visits) do
      primary_key :id

      # Real FKs — Leads, Properties, and Communities are all built modules by
      # the time Site Visits lands. All three are nullable: a visit is booked
      # against a lead that may exist without a confirmed property/community
      # yet (same reasoning as leads.property_id/community_id/area_id in
      # migrations/0014), and the visit itself may get logged before the lead
      # record is picked (walk-in style visits).
      foreign_key :lead_id, :leads
      foreign_key :property_id, :properties
      foreign_key :community_id, :communities

      String :client_name, null: false

      # Agent Network isn't built yet — deferred FK kept as a plain nullable
      # string, same pattern already established for Property#agent_slug
      # (migrations/0012) and Lead#agent_slug (migrations/0014).
      String :agent_slug

      Date :date
      String :time
      # Scheduled/Completed/Cancelled/Rescheduled — plain string with an
      # app-level allowed list (SITE_VISIT_STATUSES in
      # lib/data/siteVisits.js), same convention as Lead#status elsewhere.
      String :status, default: 'Scheduled'
      String :notes, text: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :lead_id
      index :property_id
      index :community_id
      index :status
      index :date
    end
  end
end

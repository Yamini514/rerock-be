Sequel.migration do
  change do
    create_table(:leads) do
      primary_key :id
      String :client_name, null: false
      String :client_phone, null: false
      String :client_email
      String :avatar

      # Real FKs — Properties, Communities, and Areas are all built modules
      # by the time Leads lands, so (unlike agent_slug/ram_id below) these are
      # real integer FKs. Nullable: a lead may enquire before picking a
      # specific property/community, or before an area is confirmed — the
      # mock's interestedPropertySlug/communitySlug/preferredLocation are
      # always populated in sample data, but the admin "Log Enquiry" flow this
      # replaces has always allowed creating a bare lead with just contact
      # details, so these can't be null: false.
      foreign_key :property_id, :properties
      foreign_key :community_id, :communities
      foreign_key :area_id, :areas

      Integer :budget, default: 0

      # source/priority/status are plain strings with an app-level allowed
      # list (LEAD_SOURCES/LEAD_PRIORITIES/LEAD_STATUSES in lib/data/leads.js),
      # same convention as Community#status/Property#status elsewhere — no
      # separate lookup tables for small fixed enums.
      String :source
      String :priority, default: 'Medium'
      # 7-stage funnel: New -> Contacted -> Qualified -> Site Visit Scheduled
      # -> Negotiation -> Won/Lost. This is the canonical shape adopted from
      # lib/data/leads.js, replacing lib/data/admin.js's simpler
      # leadsTable (New Lead/Contacted/Site Visit/Negotiation/Closed Won).
      String :status, default: 'New'

      Date :last_follow_up
      Date :next_follow_up

      # Agent Network and RAM aren't built yet — deferred FKs kept as plain
      # nullable strings, same pattern already established for
      # Property#agent_slug (migrations/0012).
      String :agent_slug
      String :ram_id

      # {date, event, note}[] — the lead's activity history. Client sends the
      # full array on every status-changing update (see services/leads.rb);
      # modeled as plain jsonb, same zero-custom-code precedent as
      # Property#floor_plans/#pricing_trend (migrations/0012).
      column :timeline, :jsonb, default: '[]'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :property_id
      index :community_id
      index :area_id
      index :status
      index :source
      index :priority
    end
  end
end

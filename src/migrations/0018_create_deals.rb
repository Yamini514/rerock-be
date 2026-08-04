Sequel.migration do
  change do
    create_table(:deals) do
      primary_key :id

      # Client — real nullable FK, since Clients (migrations/0017) is now a
      # built resource by the time Deals lands. Unlike Leads'/SiteVisits'
      # required `client_name` string (written before Clients existed), this
      # is the first CRM resource built *after* a real Clients table exists,
      # so the task explicitly calls for leaning toward a real FK here.
      # Nullable because a deal can originate from a lead/prospect who hasn't
      # been formalized into a full Client record yet (mirrors the mock's own
      # cross-reference note: "clientName + agentSlug pairs are cross-
      # referenced from lib/data/leads.js (deals still in progress) and
      # lib/data/clients.js (deals already closed)" — i.e. the mock itself
      # already treats "linked to a real client" as sometimes-true, not
      # always). `client_name` is kept alongside it as a plain fallback/
      # display-snapshot string (populated from the linked Client's name when
      # client_id is given, see services/deals.rb#create) so the deal always
      # has a display name even before/without a linked Client row — same
      # "real FK + fallback string" shape used for property_name below.
      foreign_key :client_id, :clients
      String :client_name, null: false

      # Property — same reasoning and same FK-plus-fallback shape as
      # client_id/client_name above: Properties (migrations/0012) is real by
      # now, but a deal's "propertyName" in the mock is sometimes a specific
      # unit string ("Sobha Royal Crest — Villa 44") that may not correspond
      # 1:1 to a single Properties row (a community's villas may be tracked
      # as one Property or several), so the free-text fallback stays
      # meaningful even once linked.
      foreign_key :property_id, :properties
      String :property_name

      # Agent Network isn't a built resource yet — deferred FK kept as a
      # plain nullable string, same pattern already established for
      # Property#agent_slug / Lead#agent_slug / SiteVisit#agent_slug /
      # Client#assigned_agent_slug.
      String :agent_slug

      Integer :value, default: 0
      Integer :probability, default: 0

      # Opportunity -> Proposal -> Negotiation -> Booking -> Closed. Plain
      # string with an app-level allowed list (DEAL_STAGES in
      # lib/data/deals.js), same convention as every other status/stage-
      # shaped field in this codebase (Lead#status, Community#status, ...).
      String :stage, default: 'Opportunity'

      Date :closing_date

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :client_id
      index :property_id
      index :agent_slug
      index :stage
    end
  end
end

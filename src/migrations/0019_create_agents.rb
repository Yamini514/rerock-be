Sequel.migration do
  change do
    # Agent Network — first resource (Agents → RAM → Portfolio Members per the
    # roadmap). Matches lib/data/agents.js's field catalog. Several
    # already-built modules (Property#agent_slug, Lead#agent_slug/#ram_id,
    # SiteVisit#agent_slug, Referral#ram_id, Client#assigned_agent_slug) all
    # deferred a plain string in place of a real FK because Agents wasn't a
    # real resource yet. That deferred-FK-promotion pass is explicitly OUT OF
    # SCOPE here — those columns are left untouched; this migration only
    # creates the new `agents` table. See ARCHITECTURE.md for the full note.
    create_table(:agents) do
      primary_key :id

      # The mock's own primary key (`slug`, e.g. "rahul-sharma") is kept as a
      # unique, real column — same "slug survives as a display/lookup field,
      # id: Integer is the real PK" convention already established for
      # Builders/Communities/Properties/etc. Routing switches to the numeric
      # id (see frontend section of ARCHITECTURE.md); slug is not the PK.
      String :slug, null: false, unique: true
      String :name, null: false
      String :role
      String :email, unique: true
      String :phone
      String :whatsapp
      String :avatar

      String :specialization
      Integer :deals_closed, default: 0
      Float :rating, default: 4.5
      Integer :experience_years, default: 0

      # Areas is a real, built module (migrations/0007) — modeled as a plain
      # Postgres integer[] column, same zero-custom-code precedent as
      # Community#amenity_ids / Property#tag_ids/#amenity_ids, rather than a
      # join table (App::Services::Base#create/#update only ever do a plain
      # set_fields/save, with no hook for pivot-table adder/remover methods —
      # see migrations/0011's own note for the full reasoning, unchanged here).
      column :strong_area_ids, 'integer[]', default: '{}'

      String :address
      # AGENT_STATUSES (lib/data/agents.js): Active / On Leave / Inactive —
      # plain string with an app-level allowed list, same convention as
      # every other status-shaped field in this codebase (Community#status,
      # Property#status, Lead#status, Client#status...).
      String :status, default: 'Active'
      String :territory

      Integer :bookings, default: 0
      Integer :revenue, default: 0
      Float :conversion_rate, default: 0
      Float :commission_rate, default: 1.5
      Integer :commission_earned, default: 0
      Integer :pending_commission, default: 0
      Integer :leads_assigned, default: 0
      Date :joined_date

      # {month, earned}[] — monthly commission trend, mirrored on every
      # PUT/update (frontend sends the full already-appended array back, same
      # "no per-entry whitelisting" convention as Property#floor_plans/
      # #pricing_trend, Lead#timeline, Client#notes/#communication_log).
      column :commission_monthly, :jsonb, default: '[]'
      # {id, title, done}[]
      column :tasks, :jsonb, default: '[]'
      # {date, status}[]
      column :attendance, :jsonb, default: '[]'
      # {id, name, value, date}[] — kept as jsonb, NOT a properties_id[] FK
      # array: these entries are historical/informational snapshots (a sale
      # price and date at the time it happened), not live pointers into the
      # properties table that should track a property's current title/price —
      # same reasoning as Client#invested_properties keeping its own
      # purchasePrice/currentValue rather than only storing a bare id.
      column :properties_sold, :jsonb, default: '[]'
      # {id, name, status}[] — same reasoning as properties_sold above: this
      # is the agent's own informal "what I'm working on" list, not a live
      # FK-backed assignment table (Properties has no agent_ids column and
      # Property#agent_slug stays a deferred string per the out-of-scope note
      # above, so there is no real join to model here yet either).
      column :properties_assigned, :jsonb, default: '[]'
      # {id, name, date, type}[] — HR-style document metadata (Aadhaar, PAN,
      # employment agreement...), unrelated to the portfolio-wide
      # lib/data/portfolio.js document mock Clients' detail page reads from.
      column :documents, :jsonb, default: '[]'
      # {title, time, done}[]
      column :activity_log, :jsonb, default: '[]'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :status
      index :territory
    end
  end
end

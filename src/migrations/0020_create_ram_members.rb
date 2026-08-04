Sequel.migration do
  change do
    # Agent Network — second resource (Agents (built) -> RAM -> Portfolio
    # Members per the roadmap). Matches lib/data/staff.js's ramTeam[] field
    # catalog. Table is named `ram_members` (not `ram`) purely to avoid an
    # awkward/reserved-sounding bare SQL identifier — the URL path (`/api/ram`,
    # `/admin/ram`) and the frontend's own route folder stay `ram` either way;
    # only the table/model/service class names say RamMembers/ram_members.
    #
    # NOT to be confused with the RAM *portal's* own self-service mocks
    # (lib/data/ramLeads.js, ramIncome.js, ramNotifications.js,
    # ramProfileExtra.js) — those stay untouched, out of scope. This migration
    # only covers the Admin portal's view of the RAM team roster.
    create_table(:ram_members) do
      primary_key :id

      # The mock's own id ("ram1", "ram2"...) is a sequential PK-shaped string,
      # not a meaningful display slug (unlike Agents' "rahul-sharma"), so it is
      # NOT reproduced as a stored column. Instead a real `slug` is generated
      # from the name at create time (same `${slugify(name)}-${suffix}` shape
      # Agents' Add form already uses) — kept as a unique, real display/lookup
      # column, not the PK, same convention as every other module. It is also
      # the column the frontend lines up against Client#assigned_ram_id (a
      # plain already-real string column, migrations/0017) on the RAM detail
      # page's "Clients" tab — two already-real string columns matching, same
      # "not a new FK" precedent as Agent#slug / Client#assigned_agent_slug.
      String :slug, null: false, unique: true
      String :name, null: false
      String :email, unique: true
      String :avatar
      String :designation

      # DECISION: buildersHandled (mock: string[] of display names, e.g.
      # ["Brigade", "Prestige"]) is promoted to a real `builder_ids integer[]`
      # FK-shaped array column here, NOT kept as free text. Builders is a
      # real, already-built module (migrations/0005) by the time RAM is being
      # built, and App::Services::Base#create/#update only ever do a plain
      # set_fields/save (no hook for pivot-table adder/remover methods) — so a
      # plain Postgres integer[] column is the same zero-custom-code precedent
      # already proven end-to-end by Agent#strong_area_ids /
      # Community#amenity_ids / Property#tag_ids/#amenity_ids, not a join
      # table. Resolved to full Builder records on the frontend by filtering
      # buildersApi's list against the id array.
      column :builder_ids, 'integer[]', default: '{}'

      String :region
      Integer :deals_this_quarter, default: 0

      # RAM_STATUSES (lib/data/staff.js): Active / Pending / Inactive — plain
      # string with an app-level allowed list, same convention as every other
      # status-shaped field (Agent#status, Community#status, Lead#status...).
      # "Pending" is the RAM portal's own self-registration state (see the
      # list page's "Approve" row action) — still just a plain PUT/update.
      String :status, default: 'Active'

      Float :satisfaction, default: 4.5
      Integer :renewal_rate, default: 80
      Integer :avg_response_time_hours, default: 4
      Integer :experience_years, default: 0
      Integer :revenue_managed, default: 0
      Integer :conversion_rate_pct, default: 0
      Integer :referral_generated, default: 0

      # {id, client, property, status}[] — sent back whole on every change,
      # same "no per-entry whitelisting" convention as Agent#commission_monthly
      # / Client#notes / Lead#timeline.
      column :recommendations, :jsonb, default: '[]'
      # {id, name, date}[]
      column :reports, :jsonb, default: '[]'
      # {month, value}[] — deals-closed trend, mirrors Agent#commission_monthly's shape.
      column :performance, :jsonb, default: '[]'
      # {title, time, description?, done}[]
      column :activities, :jsonb, default: '[]'
      # {id, name, date, type}[] — HR-style document metadata, same shape as
      # Agent#documents (unrelated to lib/data/portfolio.js's client-facing
      # document mock).
      column :documents, :jsonb, default: '[]'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :status
      index :region
    end
  end
end

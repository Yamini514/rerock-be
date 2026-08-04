Sequel.migration do
  change do
    # Agent Network — third and final resource (Agents (built) -> RAM (built)
    # -> Portfolio Members). Matches lib/data/staff.js's portfolioMembers[]
    # field catalog. Building this closes out the entire Agent Network
    # roadmap phase — see ARCHITECTURE.md.
    create_table(:portfolio_members) do
      primary_key :id

      # The mock's own id ("pm1", "pm2"...) is a sequential PK-shaped string,
      # not a meaningful display slug (unlike Agent#slug / RamMember#slug) —
      # and unlike those two, nothing else in the codebase cross-references a
      # portfolio member by any string key at all (no Client column points at
      # Portfolio Members the way Client#assigned_agent_slug/#assigned_ram_id
      # line up against Agent#slug/RamMember#slug). So no `slug` column is
      # added here — the real numeric `id` is sufficient.
      String :name, null: false
      String :email, unique: true
      String :avatar

      # clients_managed/aum/rating stay plain stored columns, matching the
      # mock's own flat shape, NOT derived from real Clients data the way
      # RamMember#clientsManaged/#portfolioValue are computed on the frontend
      # (RAM Members line up against Client#assigned_ram_id via a shared slug
      # — see migrations/0020's comments). Clients has no equivalent
      # "assigned portfolio member" column pointing at this table, so there's
      # no real join to compute these from here; they're entered directly
      # (via the drawer form or CSV import), same as the mock's own sample
      # data.
      Integer :clients_managed, default: 0
      Integer :aum, default: 0
      Float :rating, default: 0

      # DECISION: assignedRamId (mock: loose "ram1"/"ram2"/"ram3" string) is
      # promoted to a real `ram_member_id` FK, NOT kept as free text — RAM is
      # a real, already-built module (migrations/0020) by the time Portfolio
      # Members is being built, same situation Agents was in with Areas
      # (strong_area_ids) and RAM was in with Builders (builder_ids). Nullable:
      # a portfolio member may not yet be assigned to a RAM.
      foreign_key :ram_member_id, :ram_members, null: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :ram_member_id
    end
  end
end

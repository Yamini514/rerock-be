Sequel.migration do
  change do
    # DECISION (see ARCHITECTURE.md's "CRM — Clients" section for the full
    # write-up): the `clients` table already exists — migrations/0001_create_clients.rb,
    # part of the original 2-table VHRR-leftover skeleton this whole backend
    # was reused from — with an unrelated, disjoint schema: `name`, `email`
    # (unique), `assets` (jsonb), `active` (bool). Grepped the entire backend:
    # nothing live references that table/model at all — models/client.rb is
    # fully commented out, and routes.rb only ever had a *dead comment*
    # (`# r.on 'clients' do ... end`), never an active route. So there is no
    # real data or behavior riding on the old columns.
    #
    # Two options: (a) leave the old table alone and create a second,
    # differently-named table for the real CRM resource, or (b) genuinely
    # extend the existing `clients` table in place. Chose (b), for two
    # reasons:
    #   1. Table-name collision is unavoidable either way once migrations run
    #      in order — Sequel applies them sequentially, so 0001's
    #      `create_table(:clients)` will already have executed by the time
    #      this one does. A fresh `create_table(:clients)` here would just
    #      fail outright ("relation already exists"); alter_table is the only
    #      option that keeps the resource named `clients` (matching the
    #      `/clients` route and the `Client` model).
    #   2. It exactly mirrors the precedent already established in this same
    #      codebase for this same ambiguity: migrations/0004_add_role_to_users.rb
    #      extended `users` (the *other* table from the original VHRR
    #      skeleton) via a purely additive alter_table rather than creating a
    #      second "real_users" table, leaving its own dead leftover columns
    #      (`client_cookies`, `device_uuid`, `property_ids`) untouched. Two of
    #      the old clients columns even genuinely overlap with what the real
    #      resource needs (`name`, `email`) — reused as-is below.
    #
    # The old `assets` (jsonb) and `active` (bool) columns are left alone,
    # unused — same "no destructive edits to already-shipped migrations"
    # policy applied to `users.role` and its own dead leftover columns.
    # `status` below is a fresh, separate string enum column (Active/Inactive
    # per lib/data/clients.js), not a reuse of the old boolean `active`,
    # since every other status-shaped field in this codebase (Community#status,
    # Property#status, Lead#status...) is a plain string with an app-level
    # allowed list, not a boolean — keeping that convention rather than
    # overloading the dead `active` column with new meaning.
    alter_table(:clients) do
      add_column :phone, String
      add_column :avatar, String

      # `properties` (int count) and `portfolioValue` (int) from the mock are
      # both DERIVED, not stored — no columns for either. `properties` is
      # computed on the frontend as `invested_properties.length`;
      # `portfolioValue` as the sum of `invested_properties[].currentValue`.
      # See services/clients.rb / ARCHITECTURE.md for the same note.

      add_column :joined, Date, default: Sequel::CURRENT_DATE
      add_column :status, String, default: 'Active'

      # Agent Network / RAM Network aren't real resources yet — plain
      # nullable strings, same deferred-FK convention already used for
      # Property#agent_slug, Lead#agent_slug/#ram_id, SiteVisit#agent_slug,
      # Referral#ram_id.
      add_column :assigned_agent_slug, String
      add_column :assigned_ram_id, String

      add_column :type, String, default: 'Individual'
      add_column :city, String
      add_column :referral_source, String

      # Self-referential FK: a client can be referred by another client.
      # Nullable — most clients have no referrer. Two-step add_column +
      # add_foreign_key (rather than a single foreign_key call), matching
      # migrations/0004_add_role_to_users.rb's own alter_table style exactly.
      add_column :referred_by_id, Integer
      add_foreign_key [:referred_by_id], :clients, name: :fk_clients_referred_by_id

      # A client's purchased properties — kept as jsonb, not a real join
      # table, per explicit instruction: this isn't cleanly "join-table-able"
      # through the generic data_for(:save) plumbing (same reasoning as
      # Community#amenity_ids being a plain array instead of a pivot table,
      # just one step further since these rows also carry their own
      # purchasePrice/currentValue/purchaseDate, not just an id). Each entry
      # keeps `propertyId` (+ `slug`) so the frontend can link to/resolve the
      # real property via propertiesApi instead of denormalizing the name
      # into this JSON.
      add_column :invested_properties, :jsonb, default: '[]'
      add_column :notes, :jsonb, default: '[]'
      add_column :communication_log, :jsonb, default: '[]'
      add_column :timeline, :jsonb, default: '[]'

      add_index :status
      add_index :type
      add_index :referred_by_id
    end
  end
end

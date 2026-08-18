Sequel.migration do
  # Additive real FKs alongside the existing deferred `agent_slug`/`ram_id`
  # strings (both are actually Agent#slug/RamMember#slug values) — the
  # strings stay untouched and remain the live authorization key everywhere
  # (agent_portal.rb/ram_portal.rb scope every query by slug); these two
  # columns are kept in lockstep with them by models/lead.rb's
  # sync_agent_reference!/sync_ram_reference! before_validation hooks, so
  # nothing that already reads agent_slug/ram_id breaks.
  up do
    alter_table(:leads) do
      add_foreign_key :agent_id, :agents
      add_foreign_key :ram_member_id, :ram_members
      add_index :agent_id
      add_index :ram_member_id
    end

    agent_ids_by_slug = from(:agents).select_hash(:slug, :id)
    ram_ids_by_slug = from(:ram_members).select_hash(:slug, :id)

    from(:leads).exclude(agent_slug: nil).each do |row|
      aid = agent_ids_by_slug[row[:agent_slug]]
      from(:leads).where(id: row[:id]).update(agent_id: aid) if aid
    end
    from(:leads).exclude(ram_id: nil).each do |row|
      rid = ram_ids_by_slug[row[:ram_id]]
      from(:leads).where(id: row[:id]).update(ram_member_id: rid) if rid
    end
  end

  down do
    alter_table(:leads) do
      drop_column :agent_id
      drop_column :ram_member_id
    end
  end
end

Sequel.migration do
  # Same additive-FK-alongside-the-slug pattern as migrations/0088 — see
  # that file's comment. Backfilled from `assigned_agent_slug`/
  # `assigned_ram_id` (the latter is a RamMember#slug string despite its
  # name, migrations/0017).
  up do
    alter_table(:clients) do
      add_foreign_key :agent_id, :agents
      add_foreign_key :ram_member_id, :ram_members
      add_index :agent_id
      add_index :ram_member_id
    end

    agent_ids_by_slug = from(:agents).select_hash(:slug, :id)
    ram_ids_by_slug = from(:ram_members).select_hash(:slug, :id)

    from(:clients).exclude(assigned_agent_slug: nil).each do |row|
      aid = agent_ids_by_slug[row[:assigned_agent_slug]]
      from(:clients).where(id: row[:id]).update(agent_id: aid) if aid
    end
    from(:clients).exclude(assigned_ram_id: nil).each do |row|
      rid = ram_ids_by_slug[row[:assigned_ram_id]]
      from(:clients).where(id: row[:id]).update(ram_member_id: rid) if rid
    end
  end

  down do
    alter_table(:clients) do
      drop_column :agent_id
      drop_column :ram_member_id
    end
  end
end

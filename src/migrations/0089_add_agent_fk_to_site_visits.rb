Sequel.migration do
  # Same additive-FK-alongside-the-slug pattern as migrations/0088 — see
  # that file's comment. No ram_member_id here: site_visits has no ram_id
  # column at all (RAM traceability already flows through the visit's own
  # Lead — see models/site_visit.rb).
  up do
    alter_table(:site_visits) do
      add_foreign_key :agent_id, :agents
      add_index :agent_id
    end

    agent_ids_by_slug = from(:agents).select_hash(:slug, :id)
    from(:site_visits).exclude(agent_slug: nil).each do |row|
      aid = agent_ids_by_slug[row[:agent_slug]]
      from(:site_visits).where(id: row[:id]).update(agent_id: aid) if aid
    end
  end

  down do
    alter_table(:site_visits) do
      drop_column :agent_id
    end
  end
end

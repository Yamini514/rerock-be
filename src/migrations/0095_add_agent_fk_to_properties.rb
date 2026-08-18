Sequel.migration do
  # Same additive-FK-alongside-the-slug pattern already proven in
  # migrations/0088-0091 (Leads/SiteVisits/Clients/Deals) — `agent_slug`
  # stays untouched and remains live (PropertyForm.js's existing Advisor
  # Select already submits it), `agent_id` is added alongside, backfilled
  # from it, and kept in lockstep going forward by models/property.rb's
  # before_validation hook. This also closes the one Property Catalog
  # deletion gap flagged in the audit: deleting an Agent today can't be
  # blocked at all for a Property that only references it by agent_slug
  # (no FK exists to violate) — once agent_id is real, Base#delete's
  # existing Sequel::ForeignKeyConstraintViolation rescue covers it for free.
  up do
    alter_table(:properties) do
      add_foreign_key :agent_id, :agents
      add_index :agent_id
    end

    agent_ids_by_slug = from(:agents).select_hash(:slug, :id)
    from(:properties).exclude(agent_slug: nil).each do |row|
      aid = agent_ids_by_slug[row[:agent_slug]]
      from(:properties).where(id: row[:id]).update(agent_id: aid) if aid
    end
  end

  down do
    alter_table(:properties) do
      drop_column :agent_id
    end
  end
end

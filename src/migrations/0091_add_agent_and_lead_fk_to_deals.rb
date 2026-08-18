Sequel.migration do
  # `agent_id` — same additive-FK-alongside-the-slug pattern as
  # migrations/0088. `lead_id` — a genuinely new relationship (Deal never
  # had any link back to the Lead that produced it, even though
  # SiteVisit#ensure_deal_for_completion! has the lead in hand at the moment
  # it auto-creates a Deal — see models/site_visit.rb, updated alongside
  # this migration to actually stamp it going forward). Backfilled here via
  # whichever of the deal's own referral_id -> Referral#lead_id, or
  # client_id -> Lead#client_id, resolves — best-effort, nullable either way.
  up do
    alter_table(:deals) do
      add_foreign_key :agent_id, :agents
      add_foreign_key :lead_id, :leads
      add_index :agent_id
      add_index :lead_id
    end

    agent_ids_by_slug = from(:agents).select_hash(:slug, :id)
    from(:deals).exclude(agent_slug: nil).each do |row|
      aid = agent_ids_by_slug[row[:agent_slug]]
      from(:deals).where(id: row[:id]).update(agent_id: aid) if aid
    end

    referral_lead_by_id = from(:referrals).exclude(lead_id: nil).select_hash(:id, :lead_id)
    lead_id_by_client_id = from(:leads).exclude(client_id: nil).select_hash(:client_id, :id)

    from(:deals).each do |row|
      lid = row[:referral_id] ? referral_lead_by_id[row[:referral_id]] : nil
      lid ||= row[:client_id] ? lead_id_by_client_id[row[:client_id]] : nil
      from(:deals).where(id: row[:id]).update(lead_id: lid) if lid
    end
  end

  down do
    alter_table(:deals) do
      drop_column :agent_id
      drop_column :lead_id
    end
  end
end

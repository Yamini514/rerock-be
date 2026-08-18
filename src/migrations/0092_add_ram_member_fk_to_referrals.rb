Sequel.migration do
  # Same additive-FK-alongside-the-slug pattern as migrations/0088. Not
  # adding `agent_id` here — see migrations/0059's own comment: Referral's
  # `agent_slug` is carried over incidentally from the referred property,
  # not a primary assignment, and the chain already reaches Agent via
  # `referral.lead.agent_id` once Leads has the FK (migrations/0088).
  up do
    alter_table(:referrals) do
      add_foreign_key :ram_member_id, :ram_members
      add_index :ram_member_id
    end

    ram_ids_by_slug = from(:ram_members).select_hash(:slug, :id)
    from(:referrals).exclude(ram_id: nil).each do |row|
      rid = ram_ids_by_slug[row[:ram_id]]
      from(:referrals).where(id: row[:id]).update(ram_member_id: rid) if rid
    end
  end

  down do
    alter_table(:referrals) do
      drop_column :ram_member_id
    end
  end
end

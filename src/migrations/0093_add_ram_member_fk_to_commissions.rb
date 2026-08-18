Sequel.migration do
  # Same additive-FK-alongside-the-slug pattern as migrations/0088.
  up do
    alter_table(:commissions) do
      add_foreign_key :ram_member_id, :ram_members
      add_index :ram_member_id
    end

    ram_ids_by_slug = from(:ram_members).select_hash(:slug, :id)
    from(:commissions).exclude(ram_id: nil).each do |row|
      rid = ram_ids_by_slug[row[:ram_id]]
      from(:commissions).where(id: row[:id]).update(ram_member_id: rid) if rid
    end
  end

  down do
    alter_table(:commissions) do
      drop_column :ram_member_id
    end
  end
end

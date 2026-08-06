Sequel.migration do
  change do
    alter_table(:notifications) do
      # nil = broadcast to the whole `audience` (today's admin-broadcast
      # behavior, untouched). Set = only that one client/ram/agent id gets
      # it — e.g. "your site visit is scheduled" or "your document was
      # approved" shouldn't reach every other client too.
      add_column :recipient_id, Integer
      add_index [:audience, :recipient_id]
    end
  end
end

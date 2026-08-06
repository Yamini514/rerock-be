Sequel.migration do
  change do
    alter_table(:leads) do
      # Set only when the lead is known to belong to a real logged-in
      # Client account (currently: the authenticated client-portal site
      # visit booking flow) — a walk-in/public lead stays nil, same as
      # every other deferred-relationship column in this table.
      add_foreign_key :client_id, :clients
      add_index :client_id
    end
  end
end

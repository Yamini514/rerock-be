Sequel.migration do
  change do
    alter_table(:deals) do
      # Nullable, real FK — set only for deals auto-created off a completed
      # SiteVisit (services/site_visits.rb / agent_portal.rb, on status ->
      # "Completed"). A deal can still be created directly with no site
      # visit behind it at all (the existing agent-portal/admin create
      # paths), same "not every deal has one of these" shape as
      # client_id/property_id above.
      add_foreign_key :site_visit_id, :site_visits
      add_index :site_visit_id

      # Free-text notes an admin/agent can add on the deal itself — seeded
      # from the originating SiteVisit's own `notes` (if any) when a deal is
      # auto-created, then editable independently afterward.
      add_column :notes, String, text: true
    end
  end
end

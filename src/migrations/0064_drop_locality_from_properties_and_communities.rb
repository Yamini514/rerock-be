Sequel.migration do
  change do
    # Free-text `locality` (migrations/0053) removed again — reverted back
    # to relying on `area_id`/`location_id` only. services/properties.rb and
    # services/communities.rb stopped whitelisting the column first;
    # confirmed via full-repo grep that no admin/public/RAM/agent/client
    # surface still writes it before this migration was added.
    alter_table(:properties) do
      drop_column :locality
    end

    alter_table(:communities) do
      drop_column :locality
    end
  end
end

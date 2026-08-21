Sequel.migration do
  change do
    # Location (migrations/0008) was a child-of-Area locality resource that
    # never got a real admin UI — the granular Location dropdown was dropped
    # from PropertyForm.js/CommunityForm.js back in migrations/0053 (which
    # relaxed `location_id` to nullable) in favor of a free-text `locality`
    # column, and that free-text column was itself dropped again in
    # migrations/0064 with no replacement. Area has been the single real
    # "where is this" resource ever since; `location_id` on existing rows
    # was dead data with no write path, and the `locations` table had no
    # admin CRUD, no public read consumer, and no code creating new rows
    # except the sample-data seeds (models/services/frontend all updated
    # alongside this migration to stop referencing Location entirely).
    alter_table(:properties) do
      drop_column :location_id
    end

    alter_table(:communities) do
      drop_column :location_id
    end

    drop_table(:locations)
  end
end

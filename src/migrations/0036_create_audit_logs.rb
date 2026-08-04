Sequel.migration do
  change do
    create_table(:audit_logs) do
      primary_key :id

      String :module, null: false # AUDIT_MODULES: Users/Roles/Permissions/Pricing/Properties/Communities/Builders/Locations/Property Types/Settings

      # `entity` is the entity TYPE name (e.g. "Community", "User", "Role",
      # "PropertyType") per lib/data/auditLogs.js — NOT a Sequel association.
      # `entity_id` is a plain string, polymorphic FK: it points at whatever
      # entity type `entity` names, so it can't be a real `foreign_key` to
      # any single table (a Community's id and a User's id are both just
      # numbers/strings from unrelated tables). Same "plain string, no FK"
      # reasoning as activity_logs' user_name/role_name — this table must
      # also survive the referenced row being deleted or renamed later.
      String :entity, null: false
      String :entity_id, null: false

      String :changed_by # name string, not a users FK — same survives-deletion reasoning

      String :old_value, text: true
      String :new_value, text: true

      String :ip
      String :device

      # No separate `timestamp` column — `created_at` is the natural
      # "when did this change happen" field for a system-generated row,
      # same convention as activity_logs.
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :module
      index :entity
      index :entity_id
      index :changed_by
      index :created_at
    end
  end
end

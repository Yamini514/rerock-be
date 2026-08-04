Sequel.migration do
  change do
    create_table(:activity_logs) do
      primary_key :id

      # Plain strings, not FKs — per lib/data/activityLogs.js's `user`/`role`
      # (name strings, not references to real users/roles) and per this
      # module's own requirement: logs must survive a user/role being deleted
      # or renamed later, so no `user_id`/`role_id` FK back to `users`/`roles`.
      String :user_name
      String :role_name

      String :action, text: true, null: false
      String :action_type, null: false # LOG_ACTION_TYPES: Create/Update/Delete/Approve/Reject/Export/Login
      String :module, null: false # LOG_MODULES: Pricing/CRM/CMS/Site Visits/Marketing/Documents
      String :target, text: true # freeform, e.g. "Brigade Horizon" or "L-1042 -> Priya Reddy"

      String :ip
      String :browser

      String :status, null: false, default: 'Success' # LOG_STATUSES: Success/Failed
      String :severity, null: false, default: 'Info' # LOG_SEVERITIES: Info/Warning/Critical

      # No separate `time` column — `created_at` is the natural "when did
      # this happen" field for a system-generated log row; Sequel/the DB
      # already stamps it, so lib/data/activityLogs.js's `time` string field
      # doesn't need its own column.
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :module
      index :action_type
      index :status
      index :severity
      index :created_at
    end
  end
end

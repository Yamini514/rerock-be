Sequel.migration do
  # Insert-only audit trail for Lead status changes — status, when, who
  # changed it, and an optional note — kept separate from Lead#timeline
  # (a freeform, client-supplied jsonb array with no `changed_by`) precisely
  # because that column is fully trusted from the client on every save and so
  # isn't robust enough for "never overwrite previous lead status history"
  # with a guaranteed actor. Rows here are only ever written server-side by
  # services/leads.rb and services/agent_portal.rb, never edited or deleted.
  up do
    create_table(:lead_status_histories) do
      primary_key :id
      foreign_key :lead_id, :leads, null: false, on_delete: :cascade
      String :status, null: false
      String :changed_by
      String :notes, text: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :lead_id
    end
  end

  down do
    drop_table(:lead_status_histories)
  end
end

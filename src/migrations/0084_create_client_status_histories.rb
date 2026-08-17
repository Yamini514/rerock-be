Sequel.migration do
  # Insert-only audit trail for Client status changes — same shape/reasoning
  # as lead_status_histories (migrations/0081): status, when, who changed it,
  # and an optional note, written server-side only (services/clients.rb,
  # services/agent_portal.rb#update_my_client), never trusting a
  # client-supplied history row. Distinct from Client#communication_log,
  # which stays freeform/client-supplied.
  up do
    create_table(:client_status_histories) do
      primary_key :id
      foreign_key :client_id, :clients, null: false, on_delete: :cascade
      String :status, null: false
      String :changed_by
      String :notes, text: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :client_id
    end
  end

  down do
    drop_table(:client_status_histories)
  end
end

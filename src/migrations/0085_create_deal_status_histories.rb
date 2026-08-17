Sequel.migration do
  # Insert-only audit trail for Deal stage changes — same shape/reasoning as
  # lead_status_histories (migrations/0081)/client_status_histories
  # (migrations/0084): status (the deal's `stage` value), when, who changed
  # it, and an optional note, written server-side only (services/deals.rb,
  # services/agent_portal.rb#update_my_deal), never trusting a
  # client-supplied history row. Distinct from Deal#notes, which stays
  # freeform/client-supplied.
  up do
    create_table(:deal_status_histories) do
      primary_key :id
      foreign_key :deal_id, :deals, null: false, on_delete: :cascade
      String :status, null: false
      String :changed_by
      String :notes, text: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :deal_id
    end
  end

  down do
    drop_table(:deal_status_histories)
  end
end

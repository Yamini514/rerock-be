Sequel.migration do
  change do
    create_table(:notification_reads) do
      primary_key :id

      # Row existence = "this recipient has read this notification" — no
      # separate boolean needed. recipient_type/recipient_id together
      # address a client/ram_member/agent row (three separate identity
      # tables, no shared `users` row to FK against — same reasoning as
      # Notification#audience and Property#agent_slug's plain-string FKs).
      foreign_key :notification_id, :notifications, null: false
      String :recipient_type, null: false # "client" | "ram" | "agent"
      Integer :recipient_id, null: false

      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index [:notification_id, :recipient_type, :recipient_id], unique: true
      index [:recipient_type, :recipient_id]
    end
  end
end

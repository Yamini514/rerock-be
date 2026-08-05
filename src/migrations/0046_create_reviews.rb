Sequel.migration do
  change do
    create_table(:reviews) do
      primary_key :id
      foreign_key :client_id, :clients, null: false

      # Polymorphic target — "Agent" | "RamMember" | "Property" | "Builder" |
      # "Community" — a plain string + id pair rather than five separate
      # nullable FK columns, same "app-level allowed list" convention as
      # Property#status/Lead#source elsewhere in this codebase.
      String :reviewable_type, null: false
      Integer :reviewable_id, null: false

      Integer :stars, null: false
      String :quote, text: true
      String :status, default: 'Pending'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index [:reviewable_type, :reviewable_id]
      index :client_id
      index :status
    end
  end
end

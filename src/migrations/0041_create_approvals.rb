Sequel.migration do
  change do
    # Real backing table for the Dashboard's "Pending Approvals" widget
    # (previously lib/data/admin.js's local-only pendingApprovals mock, with
    # no persistence — approve/reject just spliced the item out of local
    # React state). Generic across modules on purpose, same "module-agnostic,
    # entity/entity_id polymorphic pointer" shape AuditLogs already uses
    # (migrations/0036) — a fixed AUDIT_MODULES-style enum would need a
    # migration every time a new module grows an approval step; `type` is
    # instead just a free-form label (e.g. "Testimonial", "Pricing", "Blog").
    create_table(:approvals) do
      primary_key :id

      String :type, null: false
      String :title, null: false
      String :requested_by

      # Pending / Approved / Rejected
      String :status, default: 'Pending'

      # Optional polymorphic pointer at the record this approval is about
      # (e.g. entity: "Testimonial", entity_id: "42") — same "plain string,
      # no real FK, survives the referenced row being deleted" reasoning as
      # AuditLog#entity/#entity_id. Nullable: an approval can be a freeform
      # request with nothing yet to link to.
      String :entity
      String :entity_id

      # Reviewer's note on approve/reject (e.g. a rejection reason).
      String :notes, text: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :status
      index :type
    end
  end
end
